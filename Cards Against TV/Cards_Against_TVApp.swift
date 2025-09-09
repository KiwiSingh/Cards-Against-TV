import SwiftUI
import Combine

// ---------- Models ----------
struct CompactDeck: Codable {
    let white: [String]
    let black: [CompactBlack]
    let name: String?
    let id: String?
    
    private enum CodingKeys: String, CodingKey {
        case white, black
    }
    
    init(white: [String], black: [CompactBlack], name: String? = nil, id: String? = nil) {
        self.white = white
        self.black = black
        self.name = name
        self.id = id
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.white = try container.decode([String].self, forKey: .white)
        self.black = try container.decode([CompactBlack].self, forKey: .black)
        self.name = nil
        self.id = nil
    }
}

struct CompactBlack: Codable, Identifiable {
    var id = UUID()
    let text: String
    let pick: Int
    private enum CodingKeys: String, CodingKey {
        case text, pick
    }
}
struct Player: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var score: Int = 0
    var customCardUses: Int = 0
}
enum GamePhase: Equatable {
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

// Update the data structures to match the actual JSON format
struct DeckCollection: Codable {
    let decks: [NamedDeck]?
    let white: [String]?
    let black: [CompactBlack]?
}

struct NamedDeck: Identifiable, Codable {
    var id = UUID()
    let name: String
    let white: [String]
    let black: [CompactBlack]
    let description: String?
    let official: Bool?
}

struct DeckPack: Identifiable, Codable, Equatable {
    static func == (lhs: DeckPack, rhs: DeckPack) -> Bool {
        return lhs.id == rhs.id
    }
    
    var id = UUID()
    let name: String
    let white: [Int]
    let black: [Int]
    let official: Bool?
    
    enum CodingKeys: String, CodingKey {
        case name, white, black, official
    }
}

// ---------- Deck Loader ----------
class DeckLoader: ObservableObject {
    @Published var deck: CompactDeck? = nil
    @Published var allWhiteCards: [String] = []
    @Published var allBlackCards: [CompactBlack] = []
    @Published var packs: [DeckPack] = []
    @Published var selectedPackIds: Set<UUID> = [] {
        didSet {
            createCombinedDeck()
        }
    }
    @Published var errorMessage: String? = nil
    @Published var isLoading = false
    
    var canContinue: Bool {
        !selectedPackIds.isEmpty
    }

    func loadDeckCollection() {
        guard let url = Bundle.main.url(forResource: "cah-all-compact", withExtension: "json") else {
            errorMessage = "Deck file not found in bundle."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let whiteArray = jsonObject?["white"] as? [String] {
                self.allWhiteCards = whiteArray
            }
            
            if let blackArray = jsonObject?["black"] as? [[String: Any]] {
                var compactBlacks: [CompactBlack] = []
                for blackDict in blackArray {
                    if let text = blackDict["text"] as? String,
                       let pick = blackDict["pick"] as? Int {
                        let black = CompactBlack(text: text, pick: pick)
                        compactBlacks.append(black)
                    }
                }
                self.allBlackCards = compactBlacks
            }
            
            if let packsArray = jsonObject?["packs"] as? [[String: Any]] {
                var deckPacks: [DeckPack] = []
                for packDict in packsArray {
                    if let name = packDict["name"] as? String,
                       let whiteIndices = packDict["white"] as? [Int],
                       let blackIndices = packDict["black"] as? [Int] {
                        
                        let official = packDict["official"] as? Bool
                        
                        let pack = DeckPack(
                            name: name,
                            white: whiteIndices,
                            black: blackIndices,
                            official: official
                        )
                        deckPacks.append(pack)
                    }
                }
                self.packs = deckPacks
                self.selectedPackIds = Set(deckPacks.map { $0.id })
            }
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load deck collection: \(error.localizedDescription)"
        }
    }
    
    func loadLocal() {
        loadDeckCollection()
    }
    
    func togglePackSelection(_ packId: UUID) {
        if selectedPackIds.contains(packId) {
            selectedPackIds.remove(packId)
        } else {
            selectedPackIds.insert(packId)
        }
    }
    
    func selectAllDecks() {
        selectedPackIds = Set(packs.map { $0.id })
    }
    
    func selectNoneDecks() {
        selectedPackIds.removeAll()
    }
    
    func createCombinedDeck() {
        var combinedWhiteIndices: Set<Int> = []
        var combinedBlackIndices: Set<Int> = []
        
        for pack in packs where selectedPackIds.contains(pack.id) {
            combinedWhiteIndices.formUnion(pack.white)
            combinedBlackIndices.formUnion(pack.black)
        }
        
        var combinedWhite: [String] = []
        var combinedBlack: [CompactBlack] = []
        
        for index in combinedWhiteIndices.sorted() {
            if index < allWhiteCards.count {
                combinedWhite.append(allWhiteCards[index])
            }
        }
        
        for index in combinedBlackIndices.sorted() {
            if index < allBlackCards.count {
                combinedBlack.append(allBlackCards[index])
            }
        }
        
        let combinedDeck = CompactDeck(
            white: combinedWhite,
            black: combinedBlack,
            name: "Selected Decks",
            id: "combined"
        )
        self.deck = combinedDeck
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
    
    enum AppState {
        case loading
        case deckSelection
        case playerCount
        case playerNames
        case playing
    }
    
    @State private var appState: AppState = .loading

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
                
                Group {
                    switch appState {
                    case .loading:
                        loadingView
                        
                    case .deckSelection:
                        deckSelectionView
                        
                    case .playerCount:
                        playerCountView
                        
                    case .playerNames:
                        playerNamesView
                        
                    case .playing:
                        GameView(appState: $appState)
                    }
                }
            }
            .padding()
            .onAppear {
                setupInitialState()
            }
        }
    }
    
    // MARK: - View Components
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            Text("Loading decks...")
            ProgressView()
        }
        .onAppear {
            if loader.packs.isEmpty && loader.allWhiteCards.isEmpty && !loader.isLoading {
                loader.isLoading = true
                loader.loadDeckCollection()
            }
        }
        .onChange(of: loader.packs) { packs in
            if !packs.isEmpty && appState == .loading {
                appState = .deckSelection
            }
        }
    }
    
    private var deckSelectionView: some View {
        VStack(spacing: 20) {
            Text("Select Decks")
                .font(.title)
            
            Text("Choose which decks to include in the game")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Button("Continue") {
                    if loader.canContinue {
                        appState = .playerCount
                    }
                }
                .buttonStyle(FocusableButtonStyle())
                .disabled(!loader.canContinue)
                
                Spacer()
                
                Button("Select All") {
                    loader.selectAllDecks()
                }
                .buttonStyle(FocusableButtonStyle())
                
                Button("Select None") {
                    loader.selectNoneDecks()
                }
                .buttonStyle(FocusableButtonStyle())
            }
            .padding(.horizontal)
            
            ScrollView {
                LazyVStack(spacing: 15) {
                    ForEach(loader.packs.sorted { $0.name < $1.name }) { pack in
                        Button(action: {
                            loader.togglePackSelection(pack.id)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(pack.name)
                                        .font(.title3)
                                        .foregroundColor(.primary)
                                    HStack {
                                        Text("\(pack.white.count) White Cards")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("•")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(pack.black.count) Black Cards")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: loader.selectedPackIds.contains(pack.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundColor(loader.selectedPackIds.contains(pack.id) ? .green : .gray)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.2))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var playerCountView: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                Text("Number of players:")
                
                Button {
                    if numPlayers > minPlayers {
                        numPlayers -= 1
                    }
                } label: {
                    Text("−")
                        .font(.title)
                        .frame(width: 60)
                }
                .buttonStyle(FocusableButtonStyle())
                
                Text("\(numPlayers)")
                    .frame(width: 36)
                
                Button {
                    if numPlayers < maxPlayers {
                        numPlayers += 1
                    }
                } label: {
                    Text("+")
                        .font(.title)
                        .frame(width: 60)
                }
                .buttonStyle(FocusableButtonStyle())
            }
            
            Button("Continue") {
                nameInputs = Array(repeating: "", count: numPlayers)
                currentNameIndex = 0
                askNames = true
                appState = .playerNames
            }
            .buttonStyle(FocusableButtonStyle())
            .padding(.top, 20)
            
            Spacer()
        }
    }

    private var playerNamesView: some View {
        VStack(spacing: 30) {
            Text("Enter Player Names")
                .font(.title)
            
            ForEach(0..<numPlayers, id: \.self) { index in
                HStack {
                    Text("Player \(index + 1):")
                        .frame(width: 150, alignment: .leading)
                    
                    TextField("Name", text: $nameInputs[index])
                        .padding(.horizontal)
                }
            }
            
            Button("Start Game") {
                startGame()
            }
            .buttonStyle(FocusableButtonStyle())
            .padding(.top, 20)
        }
        .padding(.horizontal, 40)
    }
    
    private func setupInitialState() {
        if loader.packs.isEmpty {
            appState = .loading
        } else {
            appState = .deckSelection
        }
    }
    
    private func startGame() {
        guard let deck = loader.deck else {
            loader.errorMessage = "No deck available to start game"
            return
        }
        let cleanedNames = nameInputs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        game.setup(with: deck, playerNames: cleanedNames)
        appState = .playing
    }
}

// ---------- Game Views ----------
struct GameView: View {
    @EnvironmentObject var game: GameState
    @State private var selectedSubmission: Int? = nil
    @State private var selectedCards: [Int] = []
    @State private var showCustomEntry: Bool = false
    @State private var customCardTexts: [String] = [""]
    @State private var showCardDetail: Bool = false
    @State private var detailCardText: String = ""

    @Binding var appState: RootView.AppState

    private enum CustomFieldFocus: Hashable {
        case field(Int)
    }
    @FocusState private var focusedCustomField: CustomFieldFocus?
    
    private func playerBackground(for index: Int) -> some View {
        Group {
            if game.roundJudge == index {
                RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 3)
            } else if game.activePlayerIndex == index && game.phase == .round {
                RoundedRectangle(cornerRadius: 8).stroke(Color.blue, lineWidth: 3)
            } else {
                Color.clear
            }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                ForEach(Array(game.players.enumerated()), id: \.offset) { idx, p in
                    VStack {
                        if game.phase == .round && game.activePlayerIndex == idx {
                            Text("Your Turn").font(.caption).bold()
                        }
                        if game.phase == .judging && game.roundJudge == idx {
                            Text("Judge").font(.caption).bold()
                        }
                        Text(p.name)
                        Text("Score: \(p.score)")
                        Text("Custom: \(p.customCardUses)/20").font(.caption2)
                    }
                    .padding(8)
                    .background(playerBackground(for: idx))
                }
            }
            Divider().frame(height: 2)
            
            if let black = game.currentBlack {
                VStack(spacing: 8) {
                    Text("Prompt:")
                    Text(black.text)
                        .font(.title2)
                        .lineLimit(nil)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            } else {
                Text("No black card available!").foregroundColor(.red)
            }
            
            if let gameerr = game.error {
                Text("Game error: \(gameerr)").foregroundColor(.red)
            }
            
            switch game.phase {
            case .waiting, .dealing:
                Text("Waiting for next round...")
            case .round:
                roundView
            case .judging:
                judgingView
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
                    Text("🎉 WE HAVE A WINNER! 🎉").font(.largeTitle).foregroundColor(.yellow)
                    ForEach(winners) { winner in
                        Text(winner.name).font(.title).foregroundColor(.white)
                    }
                    Button("Play Again") {
                        game.setup(with: game.deck!, playerNames: game.players.map { $0.name })
                    }
                    .buttonStyle(FocusableButtonStyle())
                    Button("Start New Game") {
                        appState = .deckSelection
                    }
                    .buttonStyle(FocusableButtonStyle())
                }
            }
        }
        .padding()
        .sheet(isPresented: $showCardDetail) {
            CardDetailView(cardText: detailCardText)
        }
    }
    
    private var roundView: some View {
        VStack {
            Text(game.activePlayerIndex == game.players.firstIndex(where: { $0.id == game.players[game.roundJudge].id }) ? "You are the judge this round." : "Select your card(s)")
            
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    if game.activePlayerIndex == game.players.firstIndex(where: { $0.id == game.players[game.roundJudge].id }) {
                        Text("Waiting for other players...")
                    } else {
                        ForEach(Array(game.hands[game.activePlayerIndex].enumerated()), id: \.offset) { index, card in
                            FocusableCardButton(
                                text: card,
                                isSelected: selectedCards.contains(index),
                                onTap: {
                                    if selectedCards.contains(index) {
                                        selectedCards.removeAll(where: { $0 == index })
                                    } else if selectedCards.count < (game.currentBlack?.pick ?? 1) {
                                        selectedCards.append(index)
                                    }
                                },
                                onLongPress: {
                                    detailCardText = card
                                    showCardDetail = true
                                }
                            )
                        }
                        
                        // Custom Card Button
                        if let pick = game.currentBlack?.pick, game.players[game.activePlayerIndex].customCardUses < game.maxCustomPerPlayer {
                            FocusableCustomButton(
                                isSelected: showCustomEntry,
                                pick: pick,
                                onTap: {
                                    showCustomEntry.toggle()
                                    selectedCards = [] // Deselect other cards
                                },
                                focusEnabled: !showCustomEntry
                            )
                        }
                    }
                }
                .padding()
            }
            
            if showCustomEntry {
                customCardEntryView
            } else {
                Button("Submit Card\(selectedCards.count > 1 ? "s" : "")") {
                    game.submitCard(playerIndex: game.activePlayerIndex, cardIndicesInHand: selectedCards)
                    selectedCards = []
                }
                .buttonStyle(FocusableButtonStyle())
                .disabled(selectedCards.count != (game.currentBlack?.pick ?? 1))
            }
        }
    }
    
    private var customCardEntryView: some View {
        VStack(spacing: 20) {
            let pick = game.currentBlack?.pick ?? 1
            Text("Enter \(pick) custom answer\(pick > 1 ? "s" : "") (up to 20/plyr per game)").font(.subheadline)
            ForEach(0..<pick, id: \.self) { idx in
                TextField("Custom answer #\(idx+1)...", text: Binding(
                    get: { customCardTexts.indices.contains(idx) ? customCardTexts[idx] : "" },
                    set: { v in if customCardTexts.indices.contains(idx) { customCardTexts[idx] = v } }
                ))
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(false)
                .frame(width: 400)
                .padding(8)
                .background(Color.white)
                .cornerRadius(8)
                .focused($focusedCustomField, equals: .field(idx))
                .submitLabel(idx < pick - 1 ? .next : .done)
                .onSubmit {
                    if idx < pick - 1 {
                        focusedCustomField = .field(idx + 1)
                    } else {
                        focusedCustomField = .field(idx)
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
                    .background(customCardTexts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ? Color.green : Color.gray)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(!customCardTexts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
        }
    }
    
    private var judgingView: some View {
        VStack {
            Text("Judge: Select the winning card")
            
            // Create a stable mapping between display order and original submission indices
            let shuffledSubmissions: [(displayIndex: Int, originalIndex: Int, submission: (playerIndex: Int, cards: [String]))] = {
                // Create array of (originalIndex, submission) pairs
                let indexedSubmissions = game.submissions.enumerated().map { (index: $0, submission: $1) }
                // Shuffle the pairs
                let shuffled = indexedSubmissions.shuffled()
                // Map to display format with stable indices
                return shuffled.enumerated().map { displayIdx, item in
                    (displayIndex: displayIdx, originalIndex: item.index, submission: item.submission)
                }
            }()
            
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(shuffledSubmissions, id: \.displayIndex) { item in
                        FocusableSubmissionButton(
                            cards: item.submission.cards,
                            isSelected: selectedSubmission == item.displayIndex,
                            onTap: {
                                selectedSubmission = item.displayIndex
                            },
                            onLongPress: {
                                detailCardText = item.submission.cards.joined(separator: "\n\n")
                                showCardDetail = true
                            }
                        )
                    }
                }
                .padding()
            }
            
            Button {
                if let selectedDisplayIndex = selectedSubmission {
                    // Find the original submission index from the display index
                    let originalSubmissionIndex = shuffledSubmissions[selectedDisplayIndex].originalIndex
                    game.pickWinner(submissionIndex: originalSubmissionIndex)
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
    }
}

// MARK: - Reusable Components
struct FocusableCardButton: View {
    let text: String
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    @State private var isFlipped = false
    @FocusState private var isFocused: Bool
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            cardFront
            cardBack
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
        .focusable()
        .focused($isFocused)
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0.1, perform: { onLongPress() }) { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
    
    private var cardFront: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.title3)
                .foregroundColor(.black)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColorForState, lineWidth: borderWidthForState)
        )
        .opacity(isFlipped ? 0 : 1)
    }
    
    private var cardBack: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.black)
            .shadow(radius: 5)
            .overlay(
                Image(systemName: "questionmark.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 100)
                    .colorInvert()
                    .rotation3DEffect(.degrees(180), axis: (x:0, y:1, z:0))
            )
            .rotation3DEffect(.degrees(180), axis: (x:0, y:1, z:0))
            .opacity(isFlipped ? 1 : 0)
    }
    
    private var borderColorForState: Color {
        if isSelected { return Color.green }
        if isFocused { return Color.yellow }
        return Color.gray
    }
    
    private var borderWidthForState: CGFloat {
        if isSelected { return 5 }
        if isFocused { return 3 }
        return 1
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
        VStack(spacing: 8) {
            ForEach(cards, id: \.self) { card in
                Text(card)
                    .font(.title3)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .frame(width: 420, height: 200)
        .background(backgroundColorForState)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColorForState, lineWidth: borderWidthForState)
        )
        .cornerRadius(8)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .focusable()
        .focused($isFocused)
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0.1, perform: { onLongPress() }) { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
    
    private var backgroundColorForState: Color {
        if isSelected { return Color.green.opacity(0.5) }
        if isFocused { return Color.gray.opacity(0.3) }
        return Color.gray.opacity(0.1)
    }
    
    private var borderColorForState: Color {
        if isSelected { return Color.green }
        if isFocused { return Color.blue.opacity(0.7) }
        return Color.gray
    }
    
    private var borderWidthForState: CGFloat {
        if isSelected { return 5 }
        if isFocused { return 3 }
        return 1
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
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0.1) { } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
    
    private var backgroundColorForState: Color {
        if isSelected { return Color.blue.opacity(0.5) }
        if isFocused { return Color.gray.opacity(0.3) }
        return Color.white
    }
    
    private var borderColorForState: Color {
        if isSelected { return Color.blue }
        if isFocused { return Color.blue.opacity(0.7) }
        return Color.gray
    }
    
    private var borderWidthForState: CGFloat {
        if isSelected { return 5 }
        if isFocused { return 3 }
        return 1
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
struct FocusableButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .padding()
            .background(isFocused ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}
