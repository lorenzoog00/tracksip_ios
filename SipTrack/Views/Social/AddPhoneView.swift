import SwiftUI

/// "Add your number": an optional, SMS-verified phone number, used only to find
/// friends from contacts and never shown to anyone. One screen for onboarding,
/// the one-time Social prompt and the Social profile. Adding and changing a
/// number are the same flow: `confirmPhoneCode` links or replaces as needed.
///
/// `onFinish` runs exactly once: `true` after the number is verified (and the
/// check has played), `false` for "Not now". The presenter closes the screen.
struct AddPhoneView: View {
    private let onFinish: (_ added: Bool) -> Void

    init(onFinish: @escaping (_ added: Bool) -> Void) {
        self.onFinish = onFinish
    }

    private enum Step { case number, code, done }
    private enum Field { case number, code }

    /// "Resend code" stays locked this long after each code goes out.
    private static let resendDelay: TimeInterval = 30

    @State private var step: Step = .number
    @State private var region = PhoneNumbers.defaultRegion
    /// The number as typed, formatted for `region`.
    @State private var national = ""
    @State private var showCountryPicker = false
    /// The number the current code went to, and the id Firebase gave for it.
    /// Kept through "Change number", so asking again for the same number
    /// before Resend unlocks goes back to that code instead of a new SMS.
    @State private var sentTo: String?
    @State private var verificationID: String?
    @State private var code = ""
    @State private var resendAt = Date.distantPast
    @State private var isWorking = false
    /// A code is being checked and the number linked: the one request that
    /// "Not now" must not race.
    @State private var isConfirming = false
    @State private var errorMessage: String?
    /// A non-error line, such as a resent code.
    @State private var notice: String?
    @State private var checkShown = false
    /// Guards `onFinish` so it never runs twice.
    @State private var finished = false
    /// The saved code (see `restorePendingCode`) is looked for once per screen.
    @State private var restoreChecked = false
    @FocusState private var focus: Field?

    private var country: PhoneCountry? {
        PhoneNumbers.countries.first { $0.region == region }
    }

    /// Non-nil only for a valid number of the chosen country.
    private var e164: String? {
        PhoneNumbers.e164(national: national, region: region)
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            ScrollView {
                Group {
                    switch step {
                    case .number: numberStep
                    case .code: codeStep
                    case .done: doneStep
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 48)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(.easeInOut(duration: 0.2), value: step)
        .onAppear { restorePendingCode() }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerView(selected: region) { picked in
                region = picked.region
            }
        }
        .onChange(of: national) { _, newValue in numberChanged(newValue) }
        .onChange(of: region) { _, newRegion in
            let digits = Self.digits(national)
            let formatted = digits.isEmpty ? "" : PhoneNumbers.formattedPartial(digits, region: newRegion)
            if formatted != national { national = formatted }
        }
        .onChange(of: code) { _, newValue in codeChanged(newValue) }
    }

    // MARK: - Steps

    private var numberStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Find your friends")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppColors.text)
                Text("TrackSip has a social side: see friends' nights, react and comment. Add your number to find friends from your contacts. It's never shown to anyone.")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button { showCountryPicker = true } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: "\(country?.flag ?? "") +\(country?.dialCode ?? 0)")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.text)
                    .padding(12)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Country: \(country?.name ?? region), plus \(country?.dialCode ?? 0)")
                .disabled(isWorking)

                TextField("Phone number", text: $national)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .focused($focus, equals: .number)
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.text)
                    .padding(12)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isWorking)
            }

            messages

            VStack(spacing: 10) {
                primaryButton("Send code", enabled: e164 != nil) { sendCode() }

                Text("We'll text you a code. Carrier rates may apply.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
            }

            notNowButton
        }
    }

    private var codeStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Enter the code")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppColors.text)
                Text("We texted a 6-digit code to \(PhoneNumbers.formatted(sentTo ?? "")).")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focus, equals: .code)
                .multilineTextAlignment(.center)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.text)
                .padding(14)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(isWorking)
                .accessibilityLabel("6-digit code")
                .onAppear { focus = .code }

            if isWorking {
                ProgressView().tint(AppColors.accent)
            }

            messages

            // Re-rendered every second for the countdown; nothing else polls.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = secondsUntilResend(at: context.date)
                Button { resendCode() } label: {
                    Text(remaining > 0 ? "Resend code in \(remaining)s" : "Resend code")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(remaining > 0 || isWorking ? AppColors.textTertiary : AppColors.accent)
                        .monospacedDigit()
                }
                .disabled(remaining > 0 || isWorking)
            }

            Button { changeNumber() } label: {
                Text("Change number")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .disabled(isWorking)

            notNowButton
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(AppColors.success)
                .scaleEffect(checkShown ? 1 : 0.4)
                .opacity(checkShown ? 1 : 0)
            Text("Number verified")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .opacity(checkShown ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .accessibilityElement(children: .combine)
        // Started once the step is on screen, so the check animates from small
        // and clear instead of arriving already in place.
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                checkShown = true
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder private var messages: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.danger)
                .multilineTextAlignment(.center)
        } else if let notice {
            Text(notice)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isWorking {
                    ProgressView().tint(.black)
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.accent.opacity(enabled ? 1 : 0.4))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!enabled || isWorking)
    }

    /// Off only while a code is being confirmed, so leaving can't race a number
    /// being linked. On while a code is being sent: that can hang (the silent
    /// check falling back to a reCAPTCHA page that never returns), and in
    /// onboarding this is the only way on. A send that lands after "Not now"
    /// is ignored (see `finished`).
    private var notNowButton: some View {
        Button { finish(false) } label: {
            Text("Not now")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.vertical, 6)
        }
        .disabled(isConfirming)
    }

    // MARK: - Input

    private static func digits(_ text: String) -> String {
        text.filter { character in character.isASCII && character.isWholeNumber }
    }

    /// The country and national digits of an E.164 number, when the country is
    /// one the picker offers: "+525512345678" → ("MX", "5512345678").
    private static func parts(ofE164 number: String) -> (region: String, digits: String)? {
        guard let detected = PhoneNumbers.region(ofE164: number),
              let match = PhoneNumbers.countries.first(where: { $0.region == detected }) else { return nil }
        return (detected, String(number.dropFirst(1 + String(match.dialCode).count)))
    }

    /// Formats as typed. A pasted or autofilled number that carries its country
    /// code ("+52 55 1234 5678") switches the country to match.
    private func numberChanged(_ newValue: String) {
        errorMessage = nil
        if newValue.hasPrefix("+"),
           let full = PhoneNumbers.normalize(newValue, defaultRegion: region),
           let parts = Self.parts(ofE164: full) {
            region = parts.region
            national = PhoneNumbers.formattedPartial(parts.digits, region: parts.region)
            return
        }
        let digits = Self.digits(newValue)
        let formatted = digits.isEmpty ? "" : PhoneNumbers.formattedPartial(digits, region: region)
        if formatted != newValue { national = formatted }
    }

    /// Digits only, at most six, and the sixth submits.
    private func codeChanged(_ newValue: String) {
        let digits = String(Self.digits(newValue).prefix(6))
        if digits != newValue {
            code = digits   // comes back through here, and submits then if complete
            return
        }
        if !digits.isEmpty { errorMessage = nil }
        if digits.count == 6 { confirmCode() }
    }

    private func secondsUntilResend(at date: Date) -> Int {
        max(0, Int(resendAt.timeIntervalSince(date).rounded(.up)))
    }

    // MARK: - Actions

    /// Every code is a billed SMS, so none goes out for the number the account
    /// already has, nor again for the number whose code was just sent.
    private func sendCode() {
        guard let number = e164, !isWorking else { return }
        errorMessage = nil
        notice = nil
        if number == FirebaseManager.shared.phoneNumber {
            errorMessage = "That's already your number."
            return
        }
        focus = nil
        if number == sentTo, verificationID != nil, secondsUntilResend(at: Date()) > 0 {
            code = ""
            step = .code
            return
        }
        isWorking = true
        Task {
            do {
                let id = try await FirebaseManager.shared.sendPhoneCode(to: number)
                // "Not now" while the code was on its way: the screen is closing.
                guard !finished else { return }
                let sentAt = Date()
                sentTo = number
                verificationID = id
                code = ""
                resendAt = sentAt.addingTimeInterval(Self.resendDelay)
                step = .code
                savePending(e164: number, verificationID: id, sentAt: sentAt)
            } catch {
                guard !finished else { return }
                errorMessage = FirebaseManager.phoneErrorText(error)
            }
            isWorking = false
        }
    }

    private func resendCode() {
        guard let number = sentTo, !isWorking, secondsUntilResend(at: Date()) == 0 else { return }
        isWorking = true
        errorMessage = nil
        notice = nil
        Task {
            do {
                let id = try await FirebaseManager.shared.sendPhoneCode(to: number)
                guard !finished else { return }
                let sentAt = Date()
                verificationID = id
                code = ""
                resendAt = sentAt.addingTimeInterval(Self.resendDelay)
                notice = "We sent you a new code."
                savePending(e164: number, verificationID: id, sentAt: sentAt)
            } catch {
                guard !finished else { return }
                errorMessage = FirebaseManager.phoneErrorText(error)
            }
            isWorking = false
            focus = .code
        }
    }

    private func confirmCode() {
        guard code.count == 6, let id = verificationID, !isWorking else { return }
        let entered = code
        isWorking = true
        isConfirming = true
        errorMessage = nil
        notice = nil
        Task {
            do {
                try await FirebaseManager.shared.confirmPhoneCode(entered, verificationID: id)
            } catch {
                errorMessage = FirebaseManager.phoneErrorText(error)
                code = ""
                isWorking = false
                isConfirming = false
                focus = .code
                return
            }
            isWorking = false
            isConfirming = false
            await showSuccess()
        }
    }

    /// Back to the number step. The code already sent stays valid (see `sentTo`).
    private func changeNumber() {
        guard !isWorking else { return }
        step = .number
        code = ""
        errorMessage = nil
        notice = nil
        focus = .number
    }

    /// The check scales and fades in (about 0.6 s, with the success haptic),
    /// then the screen reports back.
    private func showSuccess() async {
        focus = nil
        step = .done
        Haptics.shared.play(.success)
        try? await Task.sleep(for: .milliseconds(650))
        finish(true)
    }

    private func finish(_ added: Bool) {
        guard !finished else { return }
        finished = true
        PendingPhoneVerification.clear()
        onFinish(added)
    }

    // MARK: - Code kept across app restarts

    /// Kept on the phone so the code survives iOS closing the app while the
    /// user fetches the SMS (see `restorePendingCode`).
    private func savePending(e164 number: String, verificationID id: String, sentAt: Date) {
        guard let uid = FirebaseManager.shared.currentUserId() else { return }
        PendingPhoneVerification.save(
            PendingPhoneVerification(uid: uid, e164: number, verificationID: id, sentAt: sentAt)
        )
    }

    /// Back on the code step for a code this account was texted under ten
    /// minutes ago, instead of another billed SMS. Once per screen, and only
    /// before anything is typed; a saved code that can't come back is removed.
    private func restorePendingCode() {
        guard !restoreChecked else { return }
        restoreChecked = true
        guard step == .number, national.isEmpty, sentTo == nil else { return }
        let firebase = FirebaseManager.shared
        guard let pending = PendingPhoneVerification.load(),
              PendingPhoneVerification.isRestorable(pending, uid: firebase.currentUserId(),
                                                    accountPhone: firebase.phoneNumber, now: Date()) else {
            PendingPhoneVerification.clear()
            return
        }
        // The field shows the number again, for "Change number". A country the
        // picker doesn't offer leaves it empty; the code step works without it.
        if let parts = Self.parts(ofE164: pending.e164) {
            region = parts.region
            national = PhoneNumbers.formattedPartial(parts.digits, region: parts.region)
        }
        sentTo = pending.e164
        verificationID = pending.verificationID
        code = ""
        resendAt = pending.sentAt.addingTimeInterval(Self.resendDelay)
        step = .code
    }
}
