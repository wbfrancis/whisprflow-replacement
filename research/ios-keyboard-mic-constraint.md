# iOS custom keyboard extension: can it capture microphone audio for dictation?

## Bottom-line verdict

**No.** A custom keyboard extension (`.appex` with extension point `com.apple.keyboard-service`) cannot record microphone audio, and this is enforced at runtime by the OS, not just by policy. Apple's own documentation states flatly that "Custom keyboards, like all app extensions in iOS 8.0, have no access to the device microphone, so dictation input is not possible" ([App Extension Programming Guide: Custom Keyboard](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)). Enabling "Allow Full Access" (`RequestsOpenAccess`) does **not** change this — Full Access grants network, shared container, Location/Contacts, and iCloud, but the microphone is never in the granted set. When a keyboard extension tries to start recording anyway, the audio server rejects it because the process "is an extension and doesn't have entitlements to record audio" ([Apple Developer Forums thread 742601](https://developer.apple.com/forums/thread/742601)). The recommended architecture is therefore a **companion-app pattern**: the keyboard shows a mic button that opens (or hands off to) the containing app, the app holds `NSMicrophoneUsageDescription` and does the actual capture + speech-to-text (Speech framework / `SFSpeechRecognizer`, or `SpeechAnalyzer` on iOS 26+), writes the transcribed text into a shared App Group container, and the keyboard reads it back and inserts it. This is not seamless — it requires leaving the keyboard/current app context to record.

---

## 1. Can a custom keyboard record audio via AVAudioSession / AVAudioEngine / AVAudioRecorder while active? What happens at runtime?

**No, and it fails at runtime with an explicit entitlement error.** Apple's guide is unambiguous: keyboards "have no access to the device microphone, so dictation input is not possible" ([Custom Keyboard guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)).

The runtime behavior when a keyboard extension attempts to record: the CoreMedia audio server logs and denies the request. A developer who enabled `RequestsOpenAccess` and tried to record captured this system log ([Apple Developer Forums 742601](https://developer.apple.com/forums/thread/742601)):

> `-CMSUtilities- CMSUtility_IsAllowedToStartRecording: Client sid:0x2205e, XXXXX(17965), 'prim' with PID 17965 was NOT allowed to start recording because it is an extension and doesn't have entitlements to record audio.`

So the AVAudioSession activates but the OS refuses to start the input path; there is no data. **Evidence strength note:** the runtime-error quote comes from a developer forum post with no Apple/DTS reply, so it is a real observed log but not an Apple-authored statement. It is consistent with, and corroborates, the first-party documentation that microphone access is unavailable. The constraint has applied since **iOS 8.0** (when app extensions were introduced) and there is no primary source indicating it was ever lifted.

**Applies to:** iOS 8.0 through current (the docs still carry the same language; no primary source reverses it).

---

## 2. What does "Full Access" / `RequestsOpenAccess` actually grant and NOT grant?

`RequestsOpenAccess` is defined by Apple as "A Boolean value indicating whether a custom keyboard uses a shared container and accesses the network" ([RequestsOpenAccess reference](https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionattributes/requestsopenaccess)). The user-facing toggle is "Allow Full Access" in Settings.

**Without open access** (default sandbox), verbatim from [Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard):
- "This sandbox's default configuration disallows access to the network and prevents writing to the containing app's shared group containers (reading is permitted)."
- "No access to the file system apart from the keyboard's own sandbox container, and read-only access to the containing app's shared containers"
- **"No access to microphone and speaker"**
- "No ability to participate directly or indirectly in iCloud, Game Center, or In-App Purchase"

**With open access enabled** (Full Access on), the system adds exactly these capabilities (verbatim, same page):
- "The keyboard can access Location Services and Contacts, with user permission."
- "The keyboard and containing app can employ a shared container." (read + write)
- "The keyboard can send keystrokes and other input events for server-side processing." (network access)
- "The keyboard can use iCloud to ensure settings and the autocorrect lexicon are up to date on all devices."
- "Through the containing app, the keyboard can participate in Game Center and In-App Purchase."

**Critically, microphone is NOT in the open-access capability list.** The doc lists "No access to microphone and speaker" as a restriction, but the open-access section that follows enumerates what Full Access adds and never adds microphone or speaker to it. So Full Access grants network + shared container + location/contacts + iCloud, and does **not** grant microphone capture. This matches the runtime denial in Q1.

**Evidence strength note:** there is a mild documentation ambiguity — the "No access to microphone and speaker" bullet sits in the restricted-keyboard list, so a careless reader might infer open access removes it. It does not: the open-access list is explicit and omits microphone, and the runtime entitlement error confirms the real behavior. Treat the runtime result as authoritative.

**Applies to:** iOS 8.0+ / iPadOS 8.0+.

---

## 3. Sandbox and general API restrictions on keyboard extensions

Keyboards run in the shared app-extension sandbox with these documented limits:

- **Isolated, sandboxed process.** "Custom keyboards operate in a sandboxed environment running in an isolated process." ([Configuring open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard))
- **Reduced memory.** "Memory limits for running app extensions are significantly lower than the memory limits imposed on a foreground app." ([App Extension Programming Guide: Creating an App Extension](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionCreation.html))
- **No general background execution / no background audio.** "Although you can set up a background URL upload or download task, other types of background tasks, such as supporting VoIP or playing background audio, are not available to extensions." And: "If you include the `UIBackgroundModes` key in your app extension's `Info.plist` file, the extension will be rejected by the App Store." ([ExtensionCreation](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionCreation.html)) This kills any "keep recording in the background" idea even setting aside the mic denial.
- **Unavailable APIs.** "App extensions cannot use any API marked in header files with the `NS_EXTENSION_UNAVAILABLE` macro, or similar unavailability macro, or any API in an unavailable framework." Apple names HealthKit and the EventKit UI framework as unavailable to extensions in iOS 8.0. ([ExtensionCreation](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionCreation.html)) You must set "Require Only App-Extension-Safe API" = Yes for the target.
- **Keyboard-specific UI/interaction limits.** A custom keyboard "can draw only within the primary view of its `UIInputViewController`," "cannot select text," "cannot offer inline autocorrection controls near the insertion point," and is replaced by the system keyboard for secure text fields and phone-pad fields. ([Custom Keyboard guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html))
- **Extension type identity.** The keyboard is declared by `NSExtensionPointIdentifier` = the extension point's reverse-DNS name; keyboards use `com.apple.keyboard-service`. ([NSExtensionPointIdentifier reference](https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionpointidentifier); [App Extension Keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html))

**Applies to:** iOS 8.0+ (memory/background/unavailable-API language dates to the iOS 8 guide and has not been reversed).

---

## 4. Microphone privacy plumbing: does `NSMicrophoneUsageDescription` work from an extension?

`NSMicrophoneUsageDescription` is the required purpose string: "an iOS app linked on or after iOS 10.0 and that accesses any of the device's microphones must statically declare the intent to do so by including the NSMicrophoneUsageDescription key... If an app attempts to access any of the device's microphones without a corresponding purpose string, the app exits." ([NSMicrophoneUsageDescription reference](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSMicrophoneUsageDescription))

For a keyboard extension this key is moot: even with the purpose string present, the process is denied at the audio-server layer because it "is an extension and doesn't have entitlements to record audio" (Q1). The permission prompt is the second gate; the keyboard never clears the first (entitlement) gate, so presenting the microphone permission prompt from the keyboard is not a viable path. The **containing app** is the entity that legitimately declares `NSMicrophoneUsageDescription`, shows the prompt, and holds the recording entitlement.

**Evidence strength note:** Apple's primary docs describe `NSMicrophoneUsageDescription` in terms of "the app" and do not carve out a documented, working path for a keyboard extension to present the mic prompt and record. The blocking behavior is established by the runtime entitlement denial (a forum-captured log), not by an explicit sentence in a reference page saying "keyboards cannot show the mic prompt." The safe, documented reading: put the mic capability in the containing app.

Related documented exception (for contrast, not for keyboards): app extensions in general "cannot access the camera or microphone on an iOS device, though iMessage apps are an exception and do have access to these resources if they correctly configure the `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` Info.plist keys." This exception is specific to **iMessage** app extensions and does not extend to keyboard extensions. **Evidence strength note:** this iMessage-exception wording surfaced via Apple documentation search summaries of the App Extension Programming Guide ("Handling Common Scenarios"), but a direct fetch of that page did not re-surface the exact sentence, so treat the precise wording as lightly-sourced; the operative point for us — keyboards get no mic — is firmly sourced above.

**Applies to:** iOS 10.0+ for the usage-string requirement; the extension entitlement block applies iOS 8.0+.

---

## 5. What do real dictation/voice apps actually do to get voice-to-text near the keyboard?

None of the seamless "record straight from the keyboard" options exist. Here is each candidate and whether it is viable for a barebones dictation button.

**(a) Invoke the system dictation mic key from a third-party keyboard — not possible.**
The system dictation key belongs to Apple's standard keyboard. A custom keyboard draws only inside its own `UIInputViewController` primary view ([Custom Keyboard guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)) and has no API to trigger, observe, or embed the system dictation control. There is no documented event exposed to a keyboard extension for the system dictation key. **Not viable.**

**(b) Companion app + shared App Group container — viable, but not seamless.**
This is the standard real-world pattern. The keyboard's mic button opens the containing app; the app (which legitimately holds `NSMicrophoneUsageDescription` and the record entitlement) captures audio and transcribes it; the result is written to the shared container that Full Access enables ("The keyboard and containing app can employ a shared container" — [Configuring open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)); the keyboard reads the text back and inserts it. Requires `RequestsOpenAccess` = true for the shared container. **Viable — this is the recommended architecture.** The cost is the context switch: the user leaves the current app to the dictation app and comes back.

**(c) App Intents / Shortcuts / Siri — viable as an adjunct, still app-hosted capture.**
`AppIntents` (iOS 16+) exposes app actions to Siri, Spotlight, and Shortcuts ([App Intents](https://developer.apple.com/documentation/appintents); [SiriKit](https://developer.apple.com/documentation/sirikit)). You can define a "dictate" intent that the **containing app** fulfills (it does the mic capture and transcription). This gives a Siri/Shortcuts entry point and can pass text back, but the microphone work still happens in the app process, not the keyboard. Useful as an alternate trigger, not a way to record inside the keyboard. **Viable for triggering; capture still lives in the app.**

**(d) Action / Share extensions — no mic either.**
Action and Share extensions are ordinary app extensions and inherit the same "no camera or microphone" restriction; only iMessage app extensions are excepted (Q4). So a Share/Action extension cannot record mic audio to feed the keyboard. **Not viable for capture.**

**(e) "Open containing app, record, return" — same as (b).**
This is the concrete form of the companion-app pattern and is the one working path to real voice capture tied to a keyboard. Speech-to-text in the app uses the Speech framework: `SFSpeechRecognizer` (iOS 10+, [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)) or the newer `SpeechAnalyzer` (iOS 26+, faster and long-form, [WWDC25 "Bring advanced speech-to-text to your app"](https://developer.apple.com/videos/play/wwdc2025/277/)). **Viable — same architecture as (b).**

**Summary for a barebones seamless dictation button:** there is no seamless option. The keyboard button must hand off to the containing app (directly, or via App Intents/Shortcuts) to do the actual microphone capture, then return text through the shared App Group container. Everything else — recording in the keyboard, invoking the system dictation key, recording in a Share/Action extension — is blocked by the sandbox.

---

## Sources

1. **App Extension Programming Guide: Custom Keyboard** (Apple, archived) — states keyboards have no microphone access / no dictation, describes the restricted sandbox, open-access capabilities, and keyboard UI limits. https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html
2. **Configuring open access for a custom keyboard** (Apple, current UIKit docs) — verbatim capability/restriction lists for open access on vs off, including "No access to microphone and speaker" and the shared-container/network/location/iCloud grants. https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard
3. **RequestsOpenAccess** (Apple, Information Property List reference) — definition: "A Boolean value indicating whether a custom keyboard uses a shared container and accesses the network." https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionattributes/requestsopenaccess
4. **Apple Developer Forums thread 742601 — "Recording audio in keyboard extension"** — captures the runtime denial log: extension "doesn't have entitlements to record audio." Developer-posted, no Apple reply (weaker source, but corroborates the docs). https://developer.apple.com/forums/thread/742601
5. **App Extension Programming Guide: Creating an App Extension** (Apple, archived) — memory limits, no background audio/VoIP, `UIBackgroundModes` causes App Store rejection, `NS_EXTENSION_UNAVAILABLE` / unavailable frameworks. https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionCreation.html
6. **NSMicrophoneUsageDescription** (Apple, Information Property List reference) — required purpose string for mic access; app exits without it. https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSMicrophoneUsageDescription
7. **NSExtensionPointIdentifier** (Apple reference) and **App Extension Keys** (archived) — extension point reverse-DNS identifier; keyboards use `com.apple.keyboard-service`. https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionpointidentifier and https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html
8. **SFSpeechRecognizer** (Apple, Speech framework, iOS 10+) — speech-to-text used by containing apps. https://developer.apple.com/documentation/speech/sfspeechrecognizer
9. **WWDC25 "Bring advanced speech-to-text to your app with SpeechAnalyzer"** (Apple, iOS 26+) — newer speech-to-text API replacing SFSpeechRecognizer. https://developer.apple.com/videos/play/wwdc2025/277/
10. **App Intents** and **SiriKit** (Apple) — App Intents (iOS 16+) as an alternate trigger surface for an app-hosted dictation action. https://developer.apple.com/documentation/appintents and https://developer.apple.com/documentation/sirikit

**General caveats on evidence:** The strongest statements (no mic, sandbox limits, open-access grants) come directly from Apple's own guide and reference pages. The exact runtime failure mode (the CoreMedia entitlement error) is documented only via a developer forum log with no Apple reply — reliable as an observation, and consistent with the first-party docs, but not itself Apple-authored. The iMessage camera/mic exception wording surfaced through documentation search summaries and could not be re-confirmed word-for-word by direct page fetch, so its precise phrasing is lightly sourced; it does not affect the keyboard conclusion. No primary source indicates the microphone restriction has ever been lifted for keyboard extensions on any iOS version through the current release.
