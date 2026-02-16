import SwiftUI

struct QueryView: View {
    @EnvironmentObject private var store: FreezerStore
    @StateObject private var voice = VoiceCommandService()

    @State private var query = ""
    @State private var pendingDeleteItem: FreezerItem?
    @State private var voiceDrawerChoices: [FreezerItem] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Search") {
                    TextField("What is in the freezer?", text: $query)

                    if store.canCurrentUserEditContent {
                        Button {
                            voice.toggleListening()
                        } label: {
                            Label(
                                voice.isListening ? "Stop Listening" : "Voice Remove",
                                systemImage: voice.isListening ? "stop.circle.fill" : "mic.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.tabSelected)
                    }

                    if !voice.transcript.isEmpty {
                        Text("Live: \(voice.transcript)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(voice.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let error = voice.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if !query.freezerNormalized.isEmpty {
                    Section("Summary") {
                        Text("\(results.count) matching item\(results.count == 1 ? "" : "s")")
                        Text(totalSummary)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Results") {
                    if results.isEmpty {
                        Text("No items found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(results) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .foregroundStyle(AppTheme.itemText)
                                    HStack(spacing: 8) {
                                        CategoryBadge(text: store.categoryName(for: item.categoryID))
                                        Text(item.quantity.isEmpty ? "No quantity" : item.quantity)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.itemText)
                                        Text(store.drawerName(for: item.drawerID))
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.itemText)
                                    }
                                    Text("Added \(item.dateAdded.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.itemText)
                                }
                                Spacer()
                                if store.canCurrentUserEditContent {
                                    Button("Remove", role: .destructive) {
                                        pendingDeleteItem = item
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundStyle(AppTheme.itemText)
                                }
                            }
                            .listRowBackground(store.expiryState(for: item).rowColor)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .freezerScreenStyle()
            .onChange(of: voice.finalTranscript) { _, heard in
                guard let heard, !heard.isEmpty else { return }
                handleVoiceCommand(heard)
                voice.finalTranscript = nil
            }
            .alert("Remove item?", isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { isPresented in
                    if !isPresented { pendingDeleteItem = nil }
                }
            )) {
                Button("Cancel", role: .cancel) {
                    pendingDeleteItem = nil
                }
                Button("Remove", role: .destructive) {
                    if let item = pendingDeleteItem {
                        store.deleteItem(id: item.id)
                        voice.speak("\(item.name) removed from \(store.drawerName(for: item.drawerID)).")
                    }
                    pendingDeleteItem = nil
                }
                .disabled(!store.canCurrentUserEditContent)
            } message: {
                if let item = pendingDeleteItem {
                    Text("Remove \(item.name) from \(store.drawerName(for: item.drawerID))?")
                } else {
                    Text("This will remove the item from your freezer list.")
                }
            }
            .sheet(isPresented: Binding(
                get: { !voiceDrawerChoices.isEmpty },
                set: { show in
                    if !show { voiceDrawerChoices = [] }
                }
            )) {
                NavigationStack {
                    List {
                        Section("Choose drawer to remove from") {
                            ForEach(voiceDrawerChoices) { item in
                                Button {
                                    pendingDeleteItem = item
                                    voiceDrawerChoices = []
                                    voice.speak("\(item.name) in \(store.drawerName(for: item.drawerID)). Please confirm removal.")
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name)
                                                .foregroundStyle(AppTheme.itemText)
                                            Text(store.drawerName(for: item.drawerID))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("Added \(item.dateAdded.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("Select")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.itemText)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Voice Match")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Cancel") {
                                voiceDrawerChoices = []
                            }
                        }
                    }
                    .freezerScreenStyle()
                }
            }
        }
    }

    private var results: [FreezerItem] {
        store.matchingItems(term: query).sorted { $0.dateAdded < $1.dateAdded }
    }

    private var totalSummary: String {
        let quantities = results.map { $0.quantity.freezerNormalized }.filter { !$0.isEmpty }
        if quantities.isEmpty {
            return "No quantity values recorded"
        }
        return quantities.joined(separator: ", ")
    }

    private func handleVoiceCommand(_ heard: String) {
        guard store.canCurrentUserEditContent else {
            voice.speak("You do not have permission to remove items.")
            return
        }

        guard let command = VoiceRemoveCommand.parse(from: heard) else {
            voice.speak("I could not understand the remove command.")
            return
        }

        let matches = store.voiceRemovalMatches(itemTerm: command.itemTerm, drawerNumber: command.drawerNumber)
        guard !matches.isEmpty else {
            voice.speak("I could not find \(command.itemTerm) in the freezer.")
            return
        }

        if matches.count == 1, let item = matches.first {
            pendingDeleteItem = item
            voice.speak("\(item.name) found in \(store.drawerName(for: item.drawerID)). Please confirm removal.")
            return
        }

        voiceDrawerChoices = matches

        let uniqueDrawers = Array(Set(matches.map { store.drawerName(for: $0.drawerID) })).sorted()
        if uniqueDrawers.isEmpty {
            voice.speak("I found multiple \(command.itemTerm) items. Please choose one to remove.")
        } else {
            let drawerList = uniqueDrawers.joined(separator: ", ")
            voice.speak("I found \(command.itemTerm) in \(drawerList). Please choose which drawer to remove from.")
        }
    }
}
