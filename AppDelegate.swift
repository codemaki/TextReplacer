import Cocoa
import ApplicationServices
import IOKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let inputMonitor = InputMonitor.shared
    private let replacementManager = ReplacementManager.shared
    private var isEnabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        // Request Input Monitoring permission explicitly
        if #available(macOS 10.15, *) {
            let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            print("Input Monitoring permission granted: \(granted)")

            if !granted {
                showPermissionAlert()
            }
        }

        // Start monitoring if enabled
        if isEnabled {
            let started = inputMonitor.start()
            if !started {
                showPermissionAlert()
            }
        }

        print("TextReplacer app started")
    }

    private func showPermissionAlert() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alert = NSAlert()
            alert.messageText = "입력 모니터링 권한 설정 필요"
            alert.informativeText = """
TextReplacer가 작동하려면 입력 모니터링 권한이 필요합니다.

설정 방법:
1. 아래 버튼을 클릭하여 시스템 설정을 엽니다
2. 왼쪽 하단의 🔒 자물쇠를 클릭하고 비밀번호 입력
3. 왼쪽 목록 하단의 [+] 버튼 클릭
4. Applications 폴더에서 TextReplacer 선택
5. TextReplacer 옆의 체크박스 활성화
6. 이 앱을 재시작

⚠️ macOS 보안 정책으로 인해 수동으로 추가해야 합니다.
"""
            alert.alertStyle = .warning
            alert.addButton(withTitle: "시스템 설정 열기")
            alert.addButton(withTitle: "나중에")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateMenuBarIcon()
            button.toolTip = "TextReplacer"
        }

        updateMenu()
    }

    private func updateMenuBarIcon() {
        if let button = statusItem?.button {
            button.title = isEnabled ? "✏️" : "⏸️"
        }
    }

    private func updateMenu() {
        let menu = NSMenu()

        // Toggle enable/disable
        let toggleItem = NSMenuItem(
            title: isEnabled ? "비활성화" : "활성화",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Replacement rules section
        menu.addItem(NSMenuItem(title: "치환 규칙", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // Show current rules
        let rules = replacementManager.getRules()
        if rules.isEmpty {
            let item = NSMenuItem(title: "  (규칙 없음)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for (trigger, replacement) in rules.sorted(by: { $0.key < $1.key }) {
                let displayText = String(replacement.prefix(30)) + (replacement.count > 30 ? "..." : "")
                let item = NSMenuItem(
                    title: "  \(trigger) → \(displayText)",
                    action: #selector(editRule(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = trigger
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Add new rule
        menu.addItem(NSMenuItem(
            title: "새 규칙 추가...",
            action: #selector(addRule),
            keyEquivalent: "n"
        ))

        // Delete all rules
        if !rules.isEmpty {
            menu.addItem(NSMenuItem(
                title: "모든 규칙 삭제",
                action: #selector(deleteAllRules),
                keyEquivalent: ""
            ))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "종료",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        statusItem?.menu = menu
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()

        if isEnabled {
            inputMonitor.start()
            print("TextReplacer enabled")
        } else {
            inputMonitor.stop()
            print("TextReplacer disabled")
        }

        updateMenuBarIcon()
        updateMenu()
    }

    @objc private func addRule() {
        let alert = NSAlert()
        alert.messageText = "새 치환 규칙 추가"
        alert.informativeText = "트리거 텍스트와 치환될 텍스트를 입력하세요."
        alert.alertStyle = .informational

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 80))

        let triggerLabel = NSTextField(labelWithString: "트리거:")
        triggerLabel.frame = NSRect(x: 0, y: 56, width: 350, height: 17)
        containerView.addSubview(triggerLabel)

        let triggerField = NSTextField(frame: NSRect(x: 0, y: 34, width: 350, height: 22))
        triggerField.placeholderString = "예: ;wkaeupon"
        containerView.addSubview(triggerField)

        let replacementLabel = NSTextField(labelWithString: "치환 텍스트:")
        replacementLabel.frame = NSRect(x: 0, y: 12, width: 350, height: 17)
        containerView.addSubview(replacementLabel)

        let replacementField = NSTextField(frame: NSRect(x: 0, y: -10, width: 350, height: 22))
        replacementField.placeholderString = "예: sudo pmset disablesleep 1"
        containerView.addSubview(replacementField)

        alert.accessoryView = containerView
        alert.addButton(withTitle: "추가")
        alert.addButton(withTitle: "취소")

        alert.window.initialFirstResponder = triggerField

        if alert.runModal() == .alertFirstButtonReturn {
            let trigger = triggerField.stringValue.trimmingCharacters(in: .whitespaces)
            let replacement = replacementField.stringValue

            if !trigger.isEmpty && !replacement.isEmpty {
                replacementManager.addRule(trigger: trigger, replacement: replacement)
                updateMenu()
                print("Added rule: \(trigger) → \(replacement)")
            } else {
                showError("트리거와 치환 텍스트를 모두 입력해야 합니다.")
            }
        }
    }

    @objc private func editRule(_ sender: NSMenuItem) {
        guard let trigger = sender.representedObject as? String else { return }
        guard let currentReplacement = replacementManager.getRules()[trigger] else { return }

        let alert = NSAlert()
        alert.messageText = "규칙 편집"
        alert.informativeText = "트리거: \(trigger)"
        alert.alertStyle = .informational

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 40))

        let replacementLabel = NSTextField(labelWithString: "치환 텍스트:")
        replacementLabel.frame = NSRect(x: 0, y: 18, width: 350, height: 17)
        containerView.addSubview(replacementLabel)

        let replacementField = NSTextField(frame: NSRect(x: 0, y: -4, width: 350, height: 22))
        replacementField.stringValue = currentReplacement
        containerView.addSubview(replacementField)

        alert.accessoryView = containerView
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")

        alert.window.initialFirstResponder = replacementField

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Save
            let replacement = replacementField.stringValue
            if !replacement.isEmpty {
                replacementManager.addRule(trigger: trigger, replacement: replacement)
                updateMenu()
                print("Updated rule: \(trigger) → \(replacement)")
            } else {
                showError("치환 텍스트를 입력해야 합니다.")
            }
        } else if response == .alertSecondButtonReturn {
            // Delete
            replacementManager.removeRule(trigger: trigger)
            updateMenu()
            print("Deleted rule: \(trigger)")
        }
    }

    @objc private func deleteAllRules() {
        let alert = NSAlert()
        alert.messageText = "모든 규칙 삭제"
        alert.informativeText = "정말로 모든 치환 규칙을 삭제하시겠습니까?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")

        if alert.runModal() == .alertFirstButtonReturn {
            replacementManager.clearAllRules()
            updateMenu()
            print("All rules deleted")
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "오류"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        inputMonitor.stop()
    }
}
