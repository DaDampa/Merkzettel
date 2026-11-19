import AppKit

/// Types into the real window, to check the keys no unit test can reach:
///   APP_STORE=/tmp/x.store APP_SEED=1 APP_KEYTEST=1 Merkzettel
/// Prints PASS or FAIL per check and quits with exit code 0 or 1.
@MainActor
enum KeyTest {
    static func run(model: AppModel) async {
        setvbuf(stdout, nil, _IOLBF, 0)
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
        }
        func pause(_ seconds: Double = 0.5) async { try? await Task.sleep(for: .seconds(seconds)) }
        guard let project = model.project, let window = NSApp.windows.first(where: { $0.canBecomeMain }) else {
            print("KEYTEST FAIL no project or window")
            SelfTest.finish(code: 1)
            return
        }
        func press(_ characters: String, code: UInt16 = 0, _ flags: NSEvent.ModifierFlags = []) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                                isARepeat: false, keyCode: code) {
                    NSApp.postEvent(event, atStart: false)
                }
            }
        }
        func type(_ text: String) { for character in text { press(String(character)) } }
        let carriageReturn = "\r"

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        await pause(1)
        let tasksBefore = project.entries(.todo).count
        model.focusNewTask = true
        await pause()
        type("Tastatur")
        await pause()
        press(carriageReturn, code: 36, .shift)
        await pause(1)
        let added = project.entries(.todo).last
        check("Shift-Return adds the typed task", project.entries(.todo).count == tasksBefore + 1 && added?.text == "Tastatur", added?.text ?? "")
        type("Erste")
        await pause()
        press(carriageReturn, code: 36)
        await pause()
        type("Zweite")
        await pause()
        press(carriageReturn, code: 36)
        await pause()
        check("and the cursor is in its note line: typed text becomes notes there",
              added?.openNotes.map(\.text) == ["Erste", "Zweite"], "\(added?.openNotes.map(\.text) ?? [])")

        model.focusNewTask = true
        await pause()
        type("Nur Return")
        await pause()
        press(carriageReturn, code: 36)
        await pause()
        type("Gleich weiter")
        await pause()
        press(carriageReturn, code: 36)
        await pause()
        check("Return adds the task and stays in the task line",
              project.entries(.todo).suffix(2).map(\.text) == ["Nur Return", "Gleich weiter"], "\(project.entries(.todo).map(\.text))")

        if let note = added?.openNotes.first {
            model.activeNote = note.uuid
            await pause()
            let windowsBefore = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.count
            press(carriageReturn, code: 36, .command)
            await pause(1.5)
            let windowsAfter = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.count
            check("Command-Return opens the active note large", windowsAfter == windowsBefore + 1, "\(windowsBefore) -> \(windowsAfter)")
            // Right arrow with Option and Command, in the note window.
            if let noteWindow = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0 !== window }) {
                noteWindow.makeKeyAndOrderFront(nil)
                await pause()
                // The test app runs behind the app the person works in, so its
                // window never becomes key. Say so by hand; the rest is real.
                if model.frontNote == nil { model.frontNote = note.uuid }
                let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option, .function, .numericPad],
                                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: noteWindow.windowNumber,
                                                context: nil, characters: right, charactersIgnoringModifiers: right, isARepeat: false, keyCode: 124) {
                    NSApp.postEvent(event, atStart: false)
                }
                await pause(1)
                check("Option-Command-Right shows the next note in the same window",
                      model.activeNote == added?.openNotes.last?.uuid && noteWindow.title.contains("Tastatur"),
                      "front \(model.frontNote != nil), ticks \(model.noteStepTick), key \(noteWindow.isKeyWindow), active \(NSApp.isActive)")
            } else {
                check("the note window opened", false)
            }
        }
        // Arrow keys in the list, and the large note window following along.
        let up = String(UnicodeScalar(NSUpArrowFunctionKey)!), down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        let first = project.entries(.todo).first
        if let first, first.openNotes.count >= 2 {
            model.focusRequest = first.uuid.uuidString
            await pause()
            check("the cursor can be put on a task", model.focusedField == first.uuid.uuidString, model.focusedField ?? "none")
            press(down, code: 125, [.function, .numericPad])
            await pause()
            check("Down moves from the task to its first note", model.focusedField == first.openNotes[0].uuid.uuidString, model.focusedField ?? "none")
            let noteWindow = NSApp.windows.first { $0.isVisible && $0.canBecomeMain && $0 !== window }
            check("the large note window switches to that note",
                  model.activeNote == first.openNotes[0].uuid && noteWindow?.title.contains(first.text) == true, noteWindow?.title ?? "no window")
            press(down, code: 125, [.function, .numericPad])
            await pause()
            check("Down again moves to the second note, and the window follows",
                  model.focusedField == first.openNotes[1].uuid.uuidString && model.activeNote == first.openNotes[1].uuid)
            press(up, code: 126, [.function, .numericPad])
            press(up, code: 126, [.function, .numericPad])
            await pause()
            check("Up twice is back on the task", model.focusedField == first.uuid.uuidString, model.focusedField ?? "none")
            press(up, code: 126, [.function, .numericPad])
            await pause()
            check("Up on the first task stays there", model.focusedField == first.uuid.uuidString)
        } else {
            check("seed data has a task with two notes", false)
        }
        // Pictures. The person's clipboard is saved first and put back after.
        let board = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        func putPicture() {
            board.clearContents()
            let item = NSPasteboardItem()
            item.setData(ImageTools.sample(width: 120, height: 80, hue: 0.1), forType: .png)
            // Clipboard managers like Textsammler skip what is marked transient.
            item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            board.writeObjects([item])
        }
        if let task = project.entries(.todo).first, let note = task.openNotes.first(where: { !$0.hasImage }) {
            let before = task.openNotes.count
            putPicture()
            model.insertImage(to: project, under: task)
            await pause()
            check("the picture button adds the clipboard picture as a note", task.openNotes.count == before + 1 && task.openNotes.last?.hasImage == true)
            if let added = task.openNotes.last, added.hasImage { model.delete(added) }

            model.focusRequest = note.uuid.uuidString
            await pause()
            press("v", code: 9, .command)
            await pause(1)
            check("Command-V in a text note puts the picture into that note", note.hasImage && note.text.isEmpty == false,
                  "image \(note.hasImage), notes \(task.openNotes.count)")
            model.focusRequest = "add-\(task.uuid.uuidString)"
            await pause()
            let count = task.openNotes.count
            press("v", code: 9, .command)
            await pause(1)
            check("Command-V in the note line adds a picture note", task.openNotes.count == count + 1 && task.openNotes.last?.hasImage == true,
                  "\(count) -> \(task.openNotes.count)")
            // Text on the clipboard still pastes as text.
            board.clearContents()
            board.setString("nur Text", forType: .string)
            board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            let pictures = task.openNotes.filter(\.hasImage).count
            model.focusRequest = "add-\(task.uuid.uuidString)"
            await pause()
            press("v", code: 9, .command)
            await pause()
            check("Command-V with text on the clipboard adds no picture", task.openNotes.filter(\.hasImage).count == pictures)
        } else {
            check("seed data has a task with a text note", false)
        }
        board.clearContents()
        let items = saved.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { board.writeObjects(items) }

        print(failures == 0 ? "KEYTEST PASS" : "KEYTEST FAIL \(failures)")
        for window in NSApp.windows where window.canBecomeMain { window.close() }
        SelfTest.finish(code: failures == 0 ? 0 : 1)
    }
}
