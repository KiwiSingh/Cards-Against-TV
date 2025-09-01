# Cards Against TV
<p align="center">
  <img src="https://i.ibb.co/BJLF6y5/catv.png" alt="Cards Against TV Logo">
</p>


A local, pass-the-remote party game for Apple TV and Android, inspired by *Cards Against Humanity*. Built with SwiftUI for tvOS, and rewritten in Kotlin for Android, the game features multi-card prompts, per-turn custom answers, rotating judges, and a first-to-5 win condition.

## Features

* Local multiplayer with pass-the-remote gameplay on Apple TV and Android TV.
* Local multiplayer with pass-the-device gameplay on Android phones and tablets.
* Multi-card prompts: play 1–N answers when the black card’s pick value is greater than 1.
* In-round custom answers: players can add up to 20 custom cards per game.
* Clear visual highlights for active players and judges.
* Rotating judge each round; the first player to reach 5 points wins.

## Requirements (tvOS)

* tvOS 15 or later (officially tested only on tvOS 26)
* Xcode 15 or later
* Swift 5.7 or later
* Deck JSON included in the app bundle as `cah-all-compact.json`. You can find the source [here](https://github.com/crhallberg/json-against-humanity/blob/latest/cah-all-compact.json).

## Requirements (Android)
* Android 10 or later
* A working brain

## Setup (tvOS)

### From source

1. Create a new tvOS SwiftUI app in Xcode.
2. Download `cah-all-compact.json` and add it to your project (ensure “Copy items if needed” and target membership are checked).
3. Replace the default app entry point with the provided `Cards_Against_TVApp.swift`.
4. Set up the app icon using the included image assets:

   * The folder `Assets.xcassets` contains the image assets you're gonna need for getting the app to show up on your Apple TV's homescreen.
   * Background must be opaque; Front must match the slot’s pixel size.
5. Build and run on an Apple TV simulator or device.

### From IPA
1. Make sure Sideloadly is paired with your Apple TV device
2. Drag the IPA into Sideloadly
3. Sign and install
4. Enjoy!

## Setup (iOS/iPadOS)

### From IPA
#### Using Sideloadly (non-jailbroken devices)
1. Connect your iPhone or iPad to your MacBook or PC with a USB cable
2. Drag the Portable Edition IPA into Sideloadly
3. Sign and install
4. Enjoy!

#### Using ESign (non-jailbroken devices with working certs)
1. Download the Portable Edition IPA to your iPhone or iPad
2. Import the file into ESign
3. Use `Import app library`
4. Sign the IPA
5. Install
6. Enjoy!

#### Using TrollStore (jailbroken devices)
1. Download or AirDrop the file to your iPhone or iPad
2. Install using TrollStore
3. Enjoy!

## Setup (Android)
1. Enable installing from unknown sources
2. Download the APK
3. Install the APK
4. If prompted by Play Protect, hit "Install without scanning"
5. Enjoy!

## How to Play

* Choose the decks to play the game with. By default, all decks are selected.
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

## Screenshots (tvOS)
![Screenshot 1](https://i.ibb.co/9k6LrMLS/Screenshot-2025-08-31-at-02-26-14.png)
![Screenshot 2](https://i.ibb.co/G687gZR/Screenshot-2025-08-31-at-02-27-24.png)
![Screenshot 3](https://i.ibb.co/8gWHHWjS/Screenshot-2025-08-31-at-02-27-09.png)
![Screenshot 4](https://i.ibb.co/fG4SqTs5/Screenshot-2025-08-31-at-02-27-54.png)
![Screenshot 5](https://i.ibb.co/tpK9PB6n/Screenshot-2025-08-31-at-02-28-18.png)
![Screenshot 6](https://i.ibb.co/Xx8zmNCs/Screenshot-2025-08-31-at-02-32-40.png)

## Screenshots (Android TV)
![Screenshot 1](https://i.ibb.co/gLYP50mn/Screenshot-20250901-001742.png)
![Screenshot 2](https://i.ibb.co/sdTG7HL9/Screenshot-20250901-003328.png)
![Screenshot 3](https://i.ibb.co/chTDYzXy/Screenshot-20250901-002015.png)
![Screenshot 4](https://i.ibb.co/Rp31v0pC/Screenshot-20250901-002105.png)
![Screenshot 5](https://i.ibb.co/QjqRRTp6/Screenshot-20250901-003049.png)
![Screenshot 6](https://i.ibb.co/C535r3jm/Screenshot-20250901-002406.png)



## To-do
- Add animations

- ~~Make card text smaller~~

✅ Add deck selector ~~(idk if this is doable though)~~


## Troubleshooting

* **Deck not found**: Ensure the JSON file is named `cah-all-compact.json` and included in the app target.
* **Parse error**: Make sure the JSON is valid UTF-8.
* **App Icon errors**: The icon assets are included in `Assets.xcassets`.

## Credits
crhallberg for his amazing [JSON Against Humanity](https://github.com/crhallberg/json-against-humanity) project

## License

This is a fan-made, non-commercial project inspired by *Cards Against Humanity*. Please respect the original content’s licensing and attribution requirements.
