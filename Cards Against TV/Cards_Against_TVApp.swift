import SwiftUI
import Combine

// ---------- Models ----------
struct CompactDeck: Codable {
    let white: [String]
    let black: [CompactBlack]
}
struct CompactBlack: Codable, Identifiable {
    var id = UUID()
    let text: String
    let pick: Int
    private enum CodingKeys: String, CodingKey {
        case text, pick
    }
}
struct Player: Identifiable {
    var id = UUID()
    var name: String
    var score: Int = 0
    var customCardUses: Int = 0 // count used this game
}
enum GamePhase {
    case waiting
    case dealing
    case round
    case judging
    case showWinner
    case gameover(winners: [Player])
}

// Safe array subscript extension
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// ---------- Deck Loader -----------
class DeckLoader: ObservableObject {
    @Published var deck: CompactDeck? = nil
    @Published var errorMessage: String? = nil

    func loadLocal() {
        guard let url = Bundle.main.url(forResource: "cah-all-compact", withExtension: "json") else {
            errorMessage = "Deck file not found in bundle."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let d = try decoder.decode(CompactDeck.self, from: data)
            deck = d
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load deck: \(error.localizedDescription)"
        }
    }
}

// ---------- Game Engine ----------
class GameState: ObservableObject {
    @Published var players: [Player] = []
    @Published var hands: [[String]] = []
    @Published var usedWhiteIndices: Set<Int> = []
    @Published var usedBlackIndices: Set<Int> = []
    @Published var currentBlack: CompactBlack? = nil
    @Published var submissions: [(playerIndex: Int, cards: [String])] = []
    @Published var roundJudge: Int = 0
    @Published var phase: GamePhase = .waiting
    @Published var activePlayerIndex: Int = 0
    @Published var error: String? = nil

    let maxCustomPerPlayer = 20
    private(set) var deck: CompactDeck? = nil
    private var allWhiteCards: [String] = []
    private let handSize = 7
    let winningScore = 5

    func setup(with deck: CompactDeck, playerNames: [String]) {
        self.deck = deck
        self.allWhiteCards = deck.white
        players = playerNames.map { Player(name: $0) }
        hands = Array(repeating: [], count: players.count)
        usedWhiteIndices = []
        usedBlackIndices = []
        submissions = []
        roundJudge = 0
        phase = .dealing
        error = nil
        dealInitialHands()
        startRound()
    }

    func dealInitialHands() {
        for i in 0..<players.count {
            hands[i] = []
            var n = 0
            while hands[i].count < handSize, n < handSize * 2 {
                n += 1
                if let card = drawWhiteCard() {
                    hands[i].append(card)
                } else {
                    error = "Ran out of white cards."
                    break
                }
            }
        }
    }

    private func drawWhiteCard() -> String? {
        let total = allWhiteCards.count
        var attempts = 0
        while attempts < 100, usedWhiteIndices.count < total {
            let idx = Int.random(in: 0..<total)
            if usedWhiteIndices.contains(idx) { attempts += 1; continue }
            usedWhiteIndices.insert(idx)
            return allWhiteCards[idx]
        }
        return nil
    }
    private func drawBlackCard(from deck: CompactDeck) -> CompactBlack? {
        let total = deck.black.count
        var attempts = 0
        while attempts < 100, usedBlackIndices.count < total {
            let idx = Int.random(in: 0..<total)
            if usedBlackIndices.contains(idx) { attempts += 1; continue }
            usedBlackIndices.insert(idx)
            return deck.black[idx]
        }
        error = "Ran out of black cards."
        return nil
    }
    func startRound() {
        guard let deck = deck else { return }
        error = nil
        currentBlack = drawBlackCard(from: deck)
        if currentBlack == nil { phase = .waiting; return }
        submissions = []
        phase = .round
        activePlayerIndex = (roundJudge + 1) % players.count
        for i in 0..<players.count {
            while hands[i].count < handSize {
                if let card = drawWhiteCard() {
                    hands[i].append(card)
                } else { break }
            }
        }
    }

    func submitCard(playerIndex: Int, cardIndicesInHand: [Int]) {
        guard let hand = hands[safe: playerIndex], !cardIndicesInHand.isEmpty else { error = "No card selected."; return }
        let inOrder = cardIndicesInHand.sorted(by: >)
        var submitted: [String] = []
        var handVar = hand
        for idx in inOrder {
            guard handVar.indices.contains(idx) else { continue }
            let card = handVar.remove(at: idx)
            submitted.insert(card, at: 0)
            hands[playerIndex].remove(at: idx)
        }
        submissions.append((playerIndex: playerIndex, cards: submitted))
        for _ in submitted { refillHand(for: playerIndex) }
        advanceToNextPlayerOrJudge()
    }
    func submitCustomCard(playerIndex: Int, texts: [String]) {
        if players.indices.contains(playerIndex), players[playerIndex].customCardUses + texts.count <= maxCustomPerPlayer {
            players[playerIndex].customCardUses += texts.count
            submissions.append((playerIndex: playerIndex, cards: texts))
            advanceToNextPlayerOrJudge()
        } else {
            error = "Custom card limit exceeded!"
        }
    }
    private func advanceToNextPlayerOrJudge() {
        activePlayerIndex = (activePlayerIndex + 1) % players.count
        if activePlayerIndex == roundJudge {
            activePlayerIndex = (activePlayerIndex + 1) % players.count
        }
        if submissions.count >= players.count - 1 {
            phase = .judging
            activePlayerIndex = roundJudge
        }
    }
    func refillHand(for playerIndex: Int) {
        if let card = drawWhiteCard() {
            hands[playerIndex].append(card)
        }
    }
    func pickWinner(submissionIndex: Int) {
        guard submissions.indices.contains(submissionIndex) else {
            error = "Winner index out of bounds."
            return
        }
        let winner = submissions[submissionIndex].playerIndex
        guard players.indices.contains(winner) else {
            error = "Winner player index invalid."
            return
        }
        players[winner].score += 1
        if let maxScore = players.map(\.score).max(), maxScore >= winningScore {
            let winners = players.filter { $0.score >= winningScore }
            phase = .gameover(winners: winners)
        } else {
            phase = .showWinner
            roundJudge = (roundJudge + 1) % players.count
        }
    }
}

// ---------- Views ----------

@main
struct CardsAgainstTVApp: App {
    @StateObject private var loader = DeckLoader()
    @StateObject private var game = GameState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(loader)
                .environmentObject(game)
                .onAppear { loader.loadLocal() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var loader: DeckLoader
    @EnvironmentObject var game: GameState

    @State private var numPlayers: Int = 3
    @State private var askNames = false
    @State private var nameInputs: [String] = []
    @State private var currentNameIndex: Int = 0
    @State private var showSetup = true

    let minPlayers = 3, maxPlayers = 8

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Cards Against TV")
                    .font(.largeTitle)
                if let err = loader.errorMessage {
                    Text("Deck load error: \(err)").foregroundColor(.red)
                }
                if let gameerr = game.error {
                    Text("Game error: \(gameerr)").foregroundColor(.red)
                }
                if loader.deck == nil {
                    Text("Loading deck...")
                } else if showSetup {
                    VStack(spacing: 20) {
                        if !askNames {
                            HStack(spacing: 20) {
                                Text("Number of players:")
                                Button("–") {
                                    if numPlayers > minPlayers { numPlayers -= 1 }
                                }
                                .font(.title)
                                .frame(width: 60)
                                Text("\(numPlayers)").frame(width: 36)
                                Button("+") {
                                    if numPlayers < maxPlayers { numPlayers += 1 }
                                }
                                .font(.title)
                                .frame(width: 60)
                            }
                            Button("Continue") {
                                nameInputs = Array(repeating: "", count: numPlayers)
                                askNames = true
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            VStack(spacing: 12) {
                                Text("Player \(currentNameIndex + 1) name:")
                                TextField("Enter name", text: $nameInputs[currentNameIndex])
                                    .frame(width: 400)
                                    .padding(8)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                HStack {
                                    if currentNameIndex > 0 {
                                        Button("Back") { currentNameIndex -= 1 }
                                    }
                                    Button(currentNameIndex < numPlayers - 1 ? "Next" : "Start Game") {
                                        if !nameInputs[currentNameIndex].isEmpty {
                                            if currentNameIndex < numPlayers - 1 {
                                                currentNameIndex += 1
                                            } else {
                                                if let deck = loader.deck {
                                                    game.setup(with: deck, playerNames: nameInputs)
                                                    showSetup = false
                                                }
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }
                } else {
                    GameView()
                }
            }
            .padding()
        }
    }
}

struct GameView: View {
    @EnvironmentObject var game: GameState
    @State private var selectedSubmission: Int? = nil
    @State private var selectedCards: [Int] = [] // indices
    @State private var showCustomEntry: Bool = false
    @State private var customCardTexts: [String] = [""]
    @State private var showCardDetail: Bool = false
    @State private var detailCardText: String = ""

    // NEW: Focus for custom TextFields
    private enum CustomFieldFocus: Hashable {
        case field(Int)
    }
    @FocusState private var focusedCustomField: CustomFieldFocus?

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                ForEach(Array(game.players.enumerated()), id: \.offset) { idx, p in
                    VStack {
                        Text(p.name)
                        Text("Score: \(p.score)")
                        Text("Custom: \(p.customCardUses)/20").font(.caption2)
                    }
                    .padding(8)
                    .background(game.roundJudge == idx ? RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 3) : nil)
                }
            }
            Divider().frame(height: 2)
            if let black = game.currentBlack {
                VStack(spacing: 8) {
                    Text("Prompt:")
                    Text(black.text)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)     // PATCH for wrapping
                        .frame(maxWidth: 900)                             // PATCH for legibility
                }
            } else {
                Text("No black card available!").foregroundColor(.red)
            }
            if let gameerr = game.error {
                Text("Game error: \(gameerr)").foregroundColor(.red)
            }
            switch game.phase {
            case .round:
                if game.players.indices.contains(game.activePlayerIndex), game.hands.indices.contains(game.activePlayerIndex), let black = game.currentBlack {
                    let p = game.players[game.activePlayerIndex]
                    let pick = max(1, black.pick)
                    let customUses = p.customCardUses
                    Text("Remote holder: \(p.name)")
                    Text("Phase: Select \(pick) card(s) to play (tap in order)")
                    Text("Hold SELECT button to read a card fully")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(Array(game.hands[game.activePlayerIndex].enumerated()), id: \.offset) { idx, whiteCard in
                                let isSelected = selectedCards.contains(idx) && !showCustomEntry
                                let indexInSelection = selectedCards.firstIndex(of: idx)
                                FocusableCardButton(
                                    cardText: whiteCard,
                                    isSelected: isSelected,
                                    selectionNumber: indexInSelection != nil ? indexInSelection! + 1 : nil,
                                    onTap: {
                                        if isSelected {
                                            selectedCards.removeAll { $0 == idx }
                                        } else if selectedCards.count < pick {
                                            selectedCards.append(idx)
                                            showCustomEntry = false
                                        }
                                    },
                                    onLongPress: {
                                        detailCardText = whiteCard
                                        showCardDetail = true
                                    },
                                    focusEnabled: !showCustomEntry
                                )
                            }
                            if customUses + pick <= game.maxCustomPerPlayer {
                                FocusableCustomButton(
                                    isSelected: showCustomEntry,
                                    pick: pick,
                                    onTap: {
                                        showCustomEntry = true
                                        selectedCards = []
                                        if customCardTexts.count != pick {
                                            customCardTexts = Array(repeating: "", count: pick)
                                        }
                                        focusedCustomField = .field(0)
                                    },
                                    focusEnabled: !showCustomEntry
                                )
                            }
                        }
                        .padding()
                    }
                    .disabled(showCustomEntry)

                    // --- PATCH for explicit submit ---
                    if showCustomEntry {
                        VStack(spacing: 8) {
                            Text("Enter \(pick) custom answer\(pick > 1 ? "s" : "") (up to 20/plyr per game)").font(.subheadline)
                            ForEach(0..<pick, id: \.self) { idx in
                                TextField("Custom answer #\(idx+1)...",
                                          text: Binding(
                                            get: { customCardTexts.indices.contains(idx) ? customCardTexts[idx] : "" },
                                            set: { v in if customCardTexts.indices.contains(idx) { customCardTexts[idx] = v } }
                                          )
                                )
                                .textInputAutocapitalization(.sentences)
                                .disableAutocorrection(false)
                                .frame(width: 420)
                                .padding(8)
                                .background(Color.white)
                                .cornerRadius(8)
                                .focused($focusedCustomField, equals: .field(idx))
                                .submitLabel(idx < pick - 1 ? .next : .done)
                                .onSubmit {
                                    if idx < pick - 1 {
                                        focusedCustomField = .field(idx + 1)
                                    } else {
                                        focusedCustomField = .field(idx) // JUST stay here, do NOT auto-submit!
                                    }
                                }
                            }
                            Button {
                                let values = customCardTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                if values.allSatisfy({ !$0.isEmpty }) {
                                    game.submitCustomCard(playerIndex: game.activePlayerIndex, texts: values)
                                    customCardTexts = Array(repeating: "", count: pick)
                                    showCustomEntry = false
                                    selectedCards = []
                                    focusedCustomField = nil
                                }
                            } label: {
                                Text("Submit Custom Card\(pick > 1 ? "s" : "")")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: 420)
                                    .background(customCardTexts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ? Color.blue : Color.gray)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .disabled(!customCardTexts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
                        }
                        .onAppear {
                            focusedCustomField = .field(0)
                        }
                        .onChange(of: showCustomEntry) { newValue in
                            if newValue {
                                let p = max(1, game.currentBlack?.pick ?? 1)
                                if customCardTexts.count != p {
                                    customCardTexts = Array(repeating: "", count: p)
                                }
                                focusedCustomField = .field(0)
                            } else {
                                focusedCustomField = nil
                            }
                        }
                        .onChange(of: game.currentBlack?.pick) { _ in
                            if showCustomEntry {
                                let p = max(1, game.currentBlack?.pick ?? 1)
                                if customCardTexts.count != p {
                                    customCardTexts = Array(repeating: "", count: p)
                                }
                                focusedCustomField = .field(min(0, pick-1))
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Text("Selected: \(selectedCards.count)/\(pick) cards")
                                .foregroundColor(.secondary)
                            Button {
                                if !selectedCards.isEmpty && selectedCards.count == pick {
                                    game.submitCard(playerIndex: game.activePlayerIndex, cardIndicesInHand: selectedCards)
                                    selectedCards = []
                                    showCustomEntry = false
                                }
                            } label: {
                                Text("Submit Card\(pick > 1 ? "s" : "") (\(selectedCards.count)/\(pick))")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(selectedCards.count == pick ? Color.blue : Color.gray)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedCards.count != pick)
                        }
                    }
                } else {
                    Text("No valid player/hand for this round.")
                        .foregroundColor(.red)
                }
            case .judging:
                if game.players.indices.contains(game.roundJudge) {
                    Text("Remote holder: \(game.players[game.roundJudge].name)")
                } else {
                    Text("Remote holder: (invalid judge index)")
                }
                Text("Phase: Judge the submissions")
                Text("Hold SELECT button to read a submission fully")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    Text("Submissions (anonymized)")
                    // PATCH: explicit shuffled mapping
                    let submissionViewModels: [(viewIdx: Int, actualIdx: Int, submission: (playerIndex: Int, cards: [String]))] = {
                        let zipped = Array(game.submissions.enumerated())
                        let shuffled = zipped.shuffled()
                        return shuffled.enumerated().map { (dispIdx, zippedItem) in
                            (viewIdx: dispIdx, actualIdx: zippedItem.offset, submission: zippedItem.element)
                        }
                    }()

                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(submissionViewModels, id: \.viewIdx) { model in
                                FocusableSubmissionButton(
                                    cards: model.submission.cards,
                                    isSelected: selectedSubmission == model.viewIdx,
                                    onTap: {
                                        selectedSubmission = model.viewIdx
                                    },
                                    onLongPress: {
                                        detailCardText = model.submission.cards.joined(separator: "\n\n")
                                        showCardDetail = true
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                    Button {
                        if let s = selectedSubmission {
                            // Map from shuffled slot back to actual array
                            let actual = submissionViewModels[s].actualIdx
                            game.pickWinner(submissionIndex: actual)
                            selectedSubmission = nil
                        }
                    } label: {
                        Text("Judge: Pick Winner")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(selectedSubmission != nil ? Color.green : Color.gray)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedSubmission == nil)
                }
            case .showWinner:
                Text("Winner chosen!")
                Text("Next round starting...")
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            game.startRound()
                            selectedSubmission = nil
                            selectedCards = []
                        }
                    }
            case .gameover(let winners):
                VStack(spacing: 16) {
                    Text("🎉 WE HAVE A WINNER! 🎉").font(.largeTitle)
                    ForEach(winners) { p in
                        Text("\(p.name) wins with \(p.score) points!").font(.title)
                    }
                    Divider()
                    Text("Final Scores:").font(.title2)
                    ForEach(game.players) { p in
                        Text("\(p.name): \(p.score)")
                    }
                    Button("New Game") {
                        if let deck = game.deck {
                            game.setup(with: deck, playerNames: game.players.map { $0.name })
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 60)
            default:
                Text("Starting game...")
            }
        }
        .padding()
        .sheet(isPresented: $showCardDetail) {
            CardDetailView(cardText: detailCardText)
        }
    }
}

// MARK: - New Focusable Components

struct FocusableCardButton: View {
    let cardText: String
    let isSelected: Bool
    let selectionNumber: Int?
    let onTap: () -> Void
    let onLongPress: () -> Void
    let focusEnabled: Bool

    @FocusState private var isFocused: Bool
    @State private var isPressed = false

    var body: some View {
        Text("\(selectionNumber != nil ? "\(selectionNumber!). " : "")\(cardText)")
            .padding()
            .frame(width: 420, height: 200)
            .font(.title3)
            .multilineTextAlignment(.center)
            .foregroundColor(.black)
            .background(backgroundColorForState)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColorForState, lineWidth: borderWidthForState)
            )
            .cornerRadius(8)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .focusable(focusEnabled)
            .focused($isFocused)
            .onTapGesture {
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                onLongPress()
            } onPressingChanged: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }
    }

    private var backgroundColorForState: Color {
        if isSelected {
            return Color.blue.opacity(0.5)
        } else if isFocused {
            return Color.gray.opacity(0.3)
        } else {
            return Color.white
        }
    }

    private var borderColorForState: Color {
        if isSelected {
            return Color.blue
        } else if isFocused {
            return Color.blue.opacity(0.7)
        } else {
            return Color.gray
        }
    }

    private var borderWidthForState: CGFloat {
        if isSelected {
            return 5
        } else if isFocused {
            return 3
        } else {
            return 1
        }
    }
}

struct FocusableCustomButton: View {
    let isSelected: Bool
    let pick: Int
    let onTap: () -> Void
    let focusEnabled: Bool

    @FocusState private var isFocused: Bool
    @State private var isPressed = false

    var body: some View {
        VStack {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.largeTitle)
            Text("Write Custom \(pick > 1 ? "Cards" : "Card")")
                .padding(.top, 6)
        }
        .frame(width: 420, height: 200)
        .background(backgroundColorForState)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColorForState, lineWidth: borderWidthForState)
        )
        .cornerRadius(8)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .focusable(focusEnabled)
        .focused($isFocused)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.1) { } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }

    private var backgroundColorForState: Color {
        if isSelected {
            return Color.blue.opacity(0.5)
        } else if isFocused {
            return Color.gray.opacity(0.3)
        } else {
            return Color.white
        }
    }

    private var borderColorForState: Color {
        if isSelected {
            return Color.blue
        } else if isFocused {
            return Color.blue.opacity(0.7)
        } else {
            return Color.gray
        }
    }

    private var borderWidthForState: CGFloat {
        if isSelected {
            return 5
        } else if isFocused {
            return 3
        } else {
            return 1
        }
    }
}

struct FocusableSubmissionButton: View {
    let cards: [String]
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @FocusState private var isFocused: Bool
    @State private var isPressed = false

    var body: some View {
        VStack {
            ForEach(0..<cards.count, id: \.self) { j in
                Text(cards[j])
                    .font(.title3)
            }
        }
        .frame(width: 420, height: CGFloat(140 + cards.count * 20))
        .multilineTextAlignment(.center)
        .foregroundColor(.black)
        .background(backgroundColorForState)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColorForState, lineWidth: borderWidthForState)
        )
        .cornerRadius(8)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .focusable()
        .focused($isFocused)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            onLongPress()
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }

    private var backgroundColorForState: Color {
        if isSelected {
            return Color.green.opacity(0.5)
        } else if isFocused {
            return Color.gray.opacity(0.3)
        } else {
            return Color.white
        }
    }

    private var borderColorForState: Color {
        if isSelected {
            return Color.green
        } else if isFocused {
            return Color.blue.opacity(0.7)
        } else {
            return Color.gray
        }
    }

    private var borderWidthForState: CGFloat {
        if isSelected {
            return 5
        } else if isFocused {
            return 3
        } else {
            return 1
        }
    }
}

struct CardDetailView: View {
    let cardText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 30) {
            Text("Card Details")
                .font(.largeTitle)
                .foregroundColor(.white)
                .padding(.top, 40)

            ScrollView {
                Text(cardText)
                    .font(.title2)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .padding(40)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 5)
            }
            .frame(maxHeight: 400)

            Button("Close") {
                dismiss()
            }
            .font(.title2)
            .buttonStyle(.borderedProminent)
            .focusable()
            .padding(.bottom, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
        .ignoresSafeArea()
    }
}

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.black)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct StyledCard: View {
    let text: String
    let isBlack: Bool
    let isSelected: Bool
    let isFocused: Bool
    let isFlipped: Bool

    var body: some View {
        ZStack {
            // Card background - authentic CAH styling
            RoundedRectangle(cornerRadius: 12)
                .fill(isBlack ? Color.black : Color.white)
                .shadow(color: .black.opacity(isBlack ? 0.4 : 0.2), radius: 8, x: 0, y: 4)
            
            // Enhanced card border
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? (isBlack ? Color.yellow : Color.blue) :
                    isFocused ? Color.red :
                    Color.gray.opacity(0.6),
                    lineWidth: isSelected ? 4 : isFocused ? 3 : 2
                )
            
            // Main content with better layout
            VStack(spacing: 12) {
                // Card text - improved styling
                Text(text)
                    .font(.system(size: 26, weight: isBlack ? .heavy : .bold, design: .default))
                    .foregroundColor(isBlack ? .white : .black)
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                
                // Consistent footer on all cards - making sure it's visible
                HStack {
                    Spacer()
                    Text("CARDS AGAINST TV")
                        .font(.caption2.bold())
                        .foregroundColor(isBlack ? .white.opacity(0.7) : .black.opacity(0.6))
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            
            // Decorative elements for authentic CAH look
            if isBlack {
                // Texture for black cards
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.95),
                                Color.black,
                                Color.black.opacity(0.95)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)
                
                // Corner element for black cards
                HStack {
                    VStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 8, height: 8)
                            .padding(.top, 16)
                            .padding(.leading, 16)
                        Spacer()
                    }
                    Spacer()
                }
            } else {
                // Texture for white cards
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.95),
                                Color.white,
                                Color.white.opacity(0.95)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)
                
                // Corner element for white cards
                HStack {
                    VStack {
                        Circle()
                            .fill(Color.black.opacity(0.05))
                            .frame(width: 8, height: 8)
                            .padding(.top, 16)
                            .padding(.leading, 16)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .frame(width: 420, height: 200)
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x:0, y:1, z:0))
        .scaleEffect((isSelected || isFocused) ? 1.06 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected || isFocused)
        .animation(.spring(), value: isFlipped)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: text)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .scale.combined(with: .opacity))
        )
    }
}