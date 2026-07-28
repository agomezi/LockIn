//
//  NFCCardService.swift
//  Brickable
//
//  Core NFC wrapper for the physical lock card.
//
//  Two jobs: write the fixed identifier to a blank NTAG213/215 once
//  (`provisionCard`), and confirm on every later tap that the card presented is
//  that same card (`scanCard`). The card carries no state of its own — what a
//  tap *does* is decided from the shared container, so the card can't get out
//  of sync with the phone.
//

import Foundation
import CoreNFC

final class NFCCardService: NSObject {

    enum ServiceError: LocalizedError, Equatable {
        case unavailable
        case cancelled
        case notWritable
        case tooSmall(needed: Int, capacity: Int)
        case unrecognisedCard
        case blankCard
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "This device can't scan NFC tags."
            case .cancelled:
                return "Scan cancelled."
            case .notWritable:
                return "That card is read-only, so it can't be set up as a lock card."
            case .tooSmall(let needed, let capacity):
                return "That card is too small — it holds \(capacity) bytes and \(needed) are needed."
            case .unrecognisedCard:
                return "That's not your Brickable card."
            case .blankCard:
                return "That card is blank. Set it up as your lock card first."
            case .failed(let message):
                return message
            }
        }
    }

    private enum Operation {
        /// Write the identifier onto a fresh card.
        case provision
        /// Read a card and check it carries the identifier.
        case verify
    }

    private var session: NFCNDEFReaderSession?
    private var operation: Operation = .verify
    private var completion: ((Result<Void, Error>) -> Void)?

    var isAvailable: Bool { NFCNDEFReaderSession.readingAvailable }

    // MARK: - Public entry points

    /// One-time setup: burn the fixed identifier onto a blank card.
    func provisionCard(completion: @escaping (Result<Void, Error>) -> Void) {
        begin(.provision,
              alertMessage: "Hold your blank card against the top of your iPhone.",
              completion: completion)
    }

    /// Every subsequent tap: confirm this is the lock card.
    func scanCard(completion: @escaping (Result<Void, Error>) -> Void) {
        begin(.verify,
              alertMessage: "Hold your card against the top of your iPhone.",
              completion: completion)
    }

    // MARK: - Session lifecycle

    private func begin(_ operation: Operation,
                       alertMessage: String,
                       completion: @escaping (Result<Void, Error>) -> Void) {
        guard NFCNDEFReaderSession.readingAvailable else {
            completion(.failure(ServiceError.unavailable))
            return
        }

        // Drop any session still on screen before starting another.
        self.session?.invalidate()
        self.operation = operation
        self.completion = completion

        let session = NFCNDEFReaderSession(delegate: self,
                                           queue: nil,
                                           invalidateAfterFirstRead: false)
        session.alertMessage = alertMessage
        self.session = session
        session.begin()
    }

    /// Deliver the result exactly once, on the main queue, and tear the session
    /// down. Clearing `completion` first is what stops the subsequent
    /// `didInvalidateWithError` callback from reporting a second time.
    private func finish(_ session: NFCNDEFReaderSession?,
                        _ result: Result<Void, Error>,
                        successMessage: String? = nil,
                        errorMessage: String? = nil) {
        guard let completion else { return }
        self.completion = nil

        if let session {
            switch result {
            case .success:
                session.alertMessage = successMessage ?? "Done."
                session.invalidate()
            case .failure:
                session.invalidate(errorMessage: errorMessage ?? "Something went wrong.")
            }
        }
        self.session = nil

        DispatchQueue.main.async { completion(result) }
    }

    private var identifierPayload: NFCNDEFPayload? {
        NFCNDEFPayload.wellKnownTypeTextPayload(string: LockCard.identifier,
                                                locale: Locale(identifier: "en"))
    }

    /// True when any record on the card is our text identifier.
    private func messageCarriesIdentifier(_ message: NFCNDEFMessage) -> Bool {
        message.records.contains { record in
            let (text, _) = record.wellKnownTypeTextPayload()
            return text == LockCard.identifier
        }
    }
}

// MARK: - NFCNDEFReaderSessionDelegate

extension NFCCardService: NFCNDEFReaderSessionDelegate {

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        // Nothing to do — polling starts on its own.
    }

    /// Required by the protocol, but never called because `didDetect tags:` is
    /// implemented; that variant is the one that allows writing.
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = "Hold just one card against the phone."
            session.restartPolling()
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                self.finish(session, .failure(ServiceError.failed(error.localizedDescription)),
                            errorMessage: "Couldn't connect to that card.")
                return
            }

            tag.queryNDEFStatus { status, capacity, error in
                if let error {
                    self.finish(session, .failure(ServiceError.failed(error.localizedDescription)),
                                errorMessage: "Couldn't read that card.")
                    return
                }

                switch self.operation {
                case .provision:
                    self.write(to: tag, status: status, capacity: capacity, session: session)
                case .verify:
                    self.verify(tag: tag, status: status, session: session)
                }
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Fires for user cancel, timeout, and after our own `invalidate()`.
        // If a result already went out, `completion` is nil and this is a no-op.
        guard completion != nil else { return }

        let readerError = error as? NFCReaderError
        let isCancellation = readerError?.code == .readerSessionInvalidationErrorUserCanceled
            || readerError?.code == .readerSessionInvalidationErrorSessionTimeout

        finish(nil, .failure(isCancellation
                             ? ServiceError.cancelled
                             : ServiceError.failed(error.localizedDescription)))
    }

    // MARK: Operations

    private func write(to tag: NFCNDEFTag,
                       status: NFCNDEFStatus,
                       capacity: Int,
                       session: NFCNDEFReaderSession) {
        guard status == .readWrite else {
            let failure: ServiceError = status == .readOnly ? .notWritable : .failed("That card can't store data.")
            finish(session, .failure(failure), errorMessage: failure.localizedDescription)
            return
        }

        guard let payload = identifierPayload else {
            finish(session, .failure(ServiceError.failed("Couldn't build the card payload.")),
                   errorMessage: "Couldn't build the card payload.")
            return
        }

        let message = NFCNDEFMessage(records: [payload])
        guard message.length <= capacity else {
            let failure = ServiceError.tooSmall(needed: message.length, capacity: capacity)
            finish(session, .failure(failure), errorMessage: failure.localizedDescription)
            return
        }

        tag.writeNDEF(message) { [weak self] error in
            guard let self else { return }
            if let error {
                self.finish(session, .failure(ServiceError.failed(error.localizedDescription)),
                            errorMessage: "Couldn't write to that card.")
                return
            }
            self.finish(session, .success(()), successMessage: "Card ready.")
        }
    }

    private func verify(tag: NFCNDEFTag,
                        status: NFCNDEFStatus,
                        session: NFCNDEFReaderSession) {
        guard status != .notSupported else {
            finish(session, .failure(ServiceError.unrecognisedCard),
                   errorMessage: ServiceError.unrecognisedCard.localizedDescription)
            return
        }

        tag.readNDEF { [weak self] message, error in
            guard let self else { return }

            guard let message else {
                // A readable but empty tag reports an error here rather than an
                // empty message, so either way this is a card with nothing on it.
                _ = error
                self.finish(session, .failure(ServiceError.blankCard),
                            errorMessage: ServiceError.blankCard.localizedDescription)
                return
            }

            guard self.messageCarriesIdentifier(message) else {
                self.finish(session, .failure(ServiceError.unrecognisedCard),
                            errorMessage: ServiceError.unrecognisedCard.localizedDescription)
                return
            }

            self.finish(session, .success(()), successMessage: "Card recognised.")
        }
    }
}
