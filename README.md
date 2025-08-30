# Cards Against TV (tvOS)
<p align="center">
  <img src="https://i.ibb.co/BJLF6y5/catv.png" alt="Cards Against TV Logo">
</p>


A local, pass-the-remote party game for Apple TV inspired by *Cards Against Humanity*. Built with SwiftUI for tvOS, the game features multi-card prompts, per-turn custom answers, rotating judges, and a first-to-5 win condition.

## Features

* Local multiplayer with pass-the-remote gameplay on Apple TV.
* Multi-card prompts: play 1–N answers when the black card’s pick value is greater than 1.
* In-round custom answers: players can add up to 20 custom cards per game.
* Clear visual highlights for active players and judges.
* Rotating judge each round; the first player to reach 5 points wins.

## Requirements

* tvOS 15 or later (officially tested only on tvOS 26)
* Xcode 15 or later
* Swift 5.7 or later
* Deck JSON included in the app bundle as `cah-all-compact.json`. You can find the source [here](https://github.com/crhallberg/json-against-humanity/blob/latest/cah-all-compact.json).

## Setup

1. Create a new tvOS SwiftUI app in Xcode.
2. Download `cah-all-compact.json` and add it to your project (ensure “Copy items if needed” and target membership are checked).
3. Replace the default app entry point with the provided `Cards_Against_TVApp.swift`.
4. Set up the app icon using the included image assets:

   * The folder `Assets.xcassets` contains the image assets you're gonna need for getting the app to show up on your Apple TV's homescreen.
   * Background must be opaque; Front must match the slot’s pixel size.
5. Build and run on an Apple TV simulator or device.

## How to Play

* Choose the number of players and enter names one by one.
* Each round presents a black prompt card with a “pick” value. Non-judging players submit answers in turn.
* When multiple cards are required, players select them in order or enter custom responses.
* The judge reviews anonymized submissions and selects a winner.
* The first player to 5 points wins the game.

## JSON Deck Format

The deck file uses a simple format:

```json
{
  "white": ["An answer.", "Another answer."],
  "black": [
    { "text": "Why can't I sleep at night?", "pick": 1 },
    { "text": "I got 99 problems but _ ain't one.", "pick": 1 }
  ]
}
```

* `white` contains the answer cards.
* `black` contains prompt cards with text and a pick value.

## Screenshots
![Screenshot 1](https://i.ibb.co/mrWr0Cjp/Screenshot-2025-08-30-at-19-39-21.png)
![Screenshot 2](https://i.ibb.co/kszCDg9p/Screenshot-2025-08-30-at-19-42-01.png)
![Screenshot 3](https://i.ibb.co/xqPN6ZQR/Screenshot-2025-08-30-at-19-46-59.png)
![Screenshot 4](https://i.ibb.co/chR89fw6/Screenshot-2025-08-30-at-19-51-45.png)

## To-do
- Add animations
- Make card text smaller
- Add deck selector (idk if this is doable though)


## Troubleshooting

* **Deck not found**: Ensure the JSON file is named `cah-all-compact.json` and included in the app target.
* **Parse error**: Make sure the JSON is valid UTF-8.
* **App Icon errors**: The icon assets are included in `Assets.xcassets`.

## Credits
crhallberg for his amazing [JSON Against Humanity](https://github.com/crhallberg/json-against-humanity) project

## License

This is a fan-made, non-commercial project inspired by *Cards Against Humanity*. Please respect the original content’s licensing and attribution requirements.
