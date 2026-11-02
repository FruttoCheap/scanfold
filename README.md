# Scanfold

macOS disk usage analyzer: scans a volume and shows it as a treemap, so you can find and trash what's eating your space.

## Install

Requires macOS 14+ and Xcode.

```bash
xcodebuild -project Scanfold.xcodeproj -scheme Scanfold -configuration Release -derivedDataPath build -quiet build && ditto build/Build/Products/Release/Scanfold.app /Applications/Scanfold.app
```

Rerun after pulling changes to update the installed app.
