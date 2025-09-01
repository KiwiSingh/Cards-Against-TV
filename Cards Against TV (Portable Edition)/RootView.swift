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
struct CardsAgainstApp: App {
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
    @State private var nameInputs: [String] = []
    
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
                Text("Cards Against TV (Portable Edition)")
                    .font(.largeTitle)
                    .bold()
                
                if let err = loader.errorMessage {
                    Text("Deck load error: \(err)")
                        .foregroundColor(.red)
                        .padding()
                }
                if let gameerr = game.error {
                    Text("Game error: \(gameerr)")
                        .foregroundColor(.red)
                        .padding()
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
        .navigationViewStyle(StackNavigationViewStyle()) // Force single view on iPad
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
        .onChange(of: loader.packs) {
            if !$0.isEmpty && appState == .loading {
                appState = .deckSelection
            }
        }
    }
    
    private var deckSelectionView: some View {
        VStack(spacing: 20) {
            Text("Select Decks")
                .font(.title)
                .bold()
            
            Text("Choose which decks to include in the game")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                Button("Continue") {
                    if loader.canContinue {
                        appState = .playerCount
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!loader.canContinue)
                
                Spacer()
                
                Button("Select All") {
                    loader.selectAllDecks()
                }
                .buttonStyle(.bordered)
                
                Button("Select None") {
                    loader.selectNoneDecks()
                }
                .buttonStyle(.bordered)
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
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    HStack {
                                        Text("\(pack.white.count) White")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("•")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(pack.black.count) Black")
                                            .font(.caption)
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
                                    .fill(Color(UIColor.systemGray6))
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
        VStack(spacing: 30) {
            Text("Number of Players")
                .font(.title)
                .bold()
            
            HStack(spacing: 30) {
                Button {
                    if numPlayers > minPlayers {
                        numPlayers -= 1
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(numPlayers > minPlayers ? .blue : .gray)
                }
                .disabled(numPlayers <= minPlayers)
                
                Text("\(numPlayers)")
                    .font(.largeTitle)
                    .bold()
                    .frame(minWidth: 50)
                
                Button {
                    if numPlayers < maxPlayers {
                        numPlayers += 1
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(numPlayers < maxPlayers ? .blue : .gray)
                }
                .disabled(numPlayers >= maxPlayers)
            }
            
            Text("Players: \(minPlayers) - \(maxPlayers)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Continue") {
                nameInputs = Array(repeating: "", count: numPlayers)
                appState = .playerNames
            }
            .buttonStyle(.borderedProminent)
            .font(.headline)
            .padding(.top, 20)
            
            Spacer()
        }
    }

    private var playerNamesView: some View {
        VStack(spacing: 20) {
            Text("Enter Player Names")
                .font(.title)
                .bold()
            
            ScrollView {
                LazyVStack(spacing: 15) {
                    ForEach(0..<numPlayers, id: \.self) { index in
                        HStack {
                            Text("Player \(index + 1):")
                                .font(.headline)
                                .frame(width: 100, alignment: .leading)
                            
                            TextField("Enter name", text: $nameInputs[index])
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.words)
                                .disableAutocorrection(false)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            
            Button("Start Game") {
                startGame()
            }
            .buttonStyle(.borderedProminent)
            .font(.headline)
            .disabled(!allNamesEntered)
            .padding(.top, 20)
        }
        .padding()
    }
    
    private var allNamesEntered: Bool {
        nameInputs.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
    @State private var shuffledSubmissions: [(viewIdx: Int, actualIdx: Int, submission: (playerIndex: Int, cards: [String]))] = []

    @Binding var appState: RootView.AppState

    var body: some View {
        VStack(spacing: 20) {
            // Player Status
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Array(game.players.enumerated()), id: \.offset) { idx, player in
                        VStack(spacing: 5) {
                            if game.phase == .round && game.activePlayerIndex == idx {
                                Text("Your Turn")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                    .bold()
                            }
                            if game.phase == .judging && game.roundJudge == idx {
                                Text("Judge")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .bold()
                            }
                            Text(player.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text("Score: \(player.score)")
                                .font(.subheadline)
                            Text("Custom: \(player.customCardUses)/20")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(backgroundColorForPlayer(idx))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(borderColorForPlayer(idx), lineWidth: 2)
                                )
                        )
                    }
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            // Black Card
            if let black = game.currentBlack {
                VStack(spacing: 10) {
                    Text("Prompt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text(black.text)
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding()
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    
                    if black.pick > 1 {
                        Text("Pick \(black.pick) cards")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            
            if let gameerr = game.error {
                Text("Game error: \(gameerr)")
                    .foregroundColor(.red)
                    .padding()
            }
            
            // Game Phase Content
            Group {
                switch game.phase {
                case .waiting, .dealing:
                    Text("Preparing next round...")
                        .font(.headline)
                        .padding()
                    
                case .round:
                    roundView
                    
                case .judging:
                    judgingView
                    
                case .showWinner:
                    VStack(spacing: 15) {
                        Text("Winner chosen!")
                            .font(.title)
                            .bold()
                        Text("Next round starting...")
                            .font(.headline)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            game.startRound()
                            selectedSubmission = nil
                            selectedCards = []
                        }
                    }
                    
                case .gameover(let winners):
                    VStack(spacing: 20) {
                        Text("🎉 GAME OVER! 🎉")
                            .font(.largeTitle)
                            .bold()
                        
                        ForEach(winners) { winner in
                            Text("\(winner.name) Wins!")
                                .font(.title)
                                .bold()
                                .foregroundColor(.green)
                        }
                        
                        VStack(spacing: 15) {
                            Button("Play Again") {
                                game.setup(with: game.deck!, playerNames: game.players.map { $0.name })
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("New Game") {
                                appState = .deckSelection
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $showCardDetail) {
            CardDetailView(cardText: detailCardText)
        }
        .onChange(of: game.phase) { newPhase in
            if case .judging = newPhase {
                let zipped = Array(game.submissions.enumerated())
                let shuffled = zipped.shuffled()
                shuffledSubmissions = shuffled.enumerated().map { (dispIdx, zippedItem) in
                    (viewIdx: dispIdx, actualIdx: zippedItem.offset, submission: zippedItem.element)
                }
            }
        }
    }
    
    private func backgroundColorForPlayer(_ index: Int) -> Color {
        if game.roundJudge == index {
            return Color.orange.opacity(0.2)
        } else if game.activePlayerIndex == index && game.phase == .round {
            return Color.blue.opacity(0.2)
        } else {
            return Color(UIColor.systemGray6)
        }
    }
    
    private func borderColorForPlayer(_ index: Int) -> Color {
        if game.roundJudge == index {
            return Color.orange
        } else if game.activePlayerIndex == index && game.phase == .round {
            return Color.blue
        } else {
            return Color.clear
        }
    }
    
    private var roundView: some View {
        VStack(spacing: 20) {
            if game.activePlayerIndex == game.roundJudge {
                Text("You are the judge this round")
                    .font(.headline)
                    .padding()
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(10)
            } else {
                VStack(spacing: 15) {
                    Text("Select your card\(selectedCards.count > 1 || (game.currentBlack?.pick ?? 1) > 1 ? "s" : "")")
                        .font(.headline)
                    
                    // Cards ScrollView
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            // Player's cards
                            ForEach(Array(game.hands[game.activePlayerIndex].enumerated()), id: \.offset) { index, card in
                                CardButton(
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
                            
                            // Custom Card Option
                            if let pick = game.currentBlack?.pick,
                               game.players[game.activePlayerIndex].customCardUses < game.maxCustomPerPlayer {
                                CustomCardButton(
                                    isSelected: showCustomEntry,
                                    pick: pick,
                                    onTap: {
                                        showCustomEntry.toggle()
                                        selectedCards = []
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    if showCustomEntry {
                        customCardEntryView
                    } else {
                        Button("Submit Card\(selectedCards.count > 1 ? "s" : "")") {
                            game.submitCard(playerIndex: game.activePlayerIndex, cardIndicesInHand: selectedCards)
                            selectedCards = []
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.headline)
                        .disabled(selectedCards.count != (game.currentBlack?.pick ?? 1))
                    }
                }
            }
        }
    }
    
    private var customCardEntryView: some View {
        VStack(spacing: 20) {
            let pick = game.currentBlack?.pick ?? 1
            
            Text("Enter \(pick) custom answer\(pick > 1 ? "s" : "")")
                .font(.headline)
            
            ForEach(0..<pick, id: \.self) { idx in
                TextField("Custom answer #\(idx+1)", text: Binding(
                    get: {
                        if customCardTexts.count <= idx {
                            customCardTexts.append("")
                        }
                        return customCardTexts[idx]
                    },
                    set: { value in
                        while customCardTexts.count <= idx {
                            customCardTexts.append("")
                        }
                        customCardTexts[idx] = value
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.sentences)
            }
            
            Button("Submit Custom Card\(pick > 1 ? "s" : "")") {
                let values = customCardTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if values.allSatisfy({ !$0.isEmpty }) {
                    game.submitCustomCard(playerIndex: game.activePlayerIndex, texts: values)
                    customCardTexts = Array(repeating: "", count: pick)
                    showCustomEntry = false
                    selectedCards = []
                }
            }
            .buttonStyle(.borderedProminent)
            .font(.headline)
            .disabled(!customCardTexts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(15)
    }
    
    private var judgingView: some View {
        VStack(spacing: 20) {
            Text("Judge: Select the winning card")
                .font(.headline)
                .bold()
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(shuffledSubmissions, id: \.viewIdx) { model in
                        SubmissionButton(
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
                .padding(.horizontal)
            }
            
            Button("Pick Winner") {
                if let s = selectedSubmission, let model = shuffledSubmissions.first(where: { $0.viewIdx == s }) {
                    let actual = model.actualIdx
                    game.pickWinner(submissionIndex: actual)
                    selectedSubmission = nil
                }
            }
            .buttonStyle(.borderedProminent)
            .font(.headline)
            .disabled(selectedSubmission == nil)
        }
    }
}

// MARK: - Card Components
struct CardButton: View {
    let text: String
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.body)
                .foregroundColor(.black)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .padding(15)
            Spacer(minLength: 0)
        }
        .frame(width: 200, height: 140)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.green : Color.gray, lineWidth: isSelected ? 3 : 1)
        )
        .cornerRadius(12)
        .shadow(radius: 3)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            onLongPress()
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }
}

struct SubmissionButton: View {
    let cards: [String]
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                Text(card)
                    .font(.body)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(8)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 200, height: 140)
        .background(isSelected ? Color.green.opacity(0.3) : Color(UIColor.systemGray6))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.green : Color.gray, lineWidth: isSelected ? 3 : 1)
        )
        .cornerRadius(12)
        .shadow(radius: 3)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            onLongPress()
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }
}

struct CustomCardButton: View {
    let isSelected: Bool
    let pick: Int
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.largeTitle)
                .foregroundColor(.blue)
            
            Text("Write Custom")
                .font(.headline)
                .bold()
            
            Text("\(pick > 1 ? "Cards" : "Card")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(width: 200, height: 140)
        .background(isSelected ? Color.blue.opacity(0.3) : Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.gray, lineWidth: isSelected ? 3 : 1)
        )
        .cornerRadius(12)
        .shadow(radius: 3)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.1) {
            // No action on long press for custom button
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }
}

struct CardDetailView: View {
    let cardText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                ScrollView {
                    Text(cardText)
                        .font(.title2)
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .padding(30)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(15)
                        .shadow(radius: 5)
                }
                .frame(maxHeight: 400)
            }
            .padding()
            .navigationTitle("Card Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}