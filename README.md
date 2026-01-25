# sidplay5
Sidplay for macOS

Since it seems that Sidplay 4.2 (http://www.sidmusic.org/sidplay/mac/) is no longer developed I decided to update the source and provide binaries for Intel and Apple Silicon. 

# implemented changes
* 64 Bit binary, runs on macOS 10.9 or higher
* supports Intel and Apple Silicon
* code compiles now on latest Xcode
* auto-update feature disabled (for now)
* supports new song length database format
* expanded toolbar (old Mac OS X look&feel)
* SIDBlaster USB support (still not complete, digi songs will have issues)
* uses now libsidplayerfp (https://github.com/libsidplayfp/libsidplayfp)

# still need to fix
* Xcode still complains about missing UI constraints and OpenGL
* ~~starting with macOS 11, the toolbar height is smaller and the track info is cut off, stepping through subtunes is now a little bit tricky~~

# build and sign
## local build (unsigned) + ad-hoc signing
Build without a signing identity, then ad-hoc sign for local use:
```
xcodebuild -project SIDPLAY.xcodeproj -scheme SIDPLAY -configuration Release build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_STYLE=Manual \
  -derivedDataPath build/DerivedData
```

Ad-hoc sign embedded components first, then the app:
```
codesign --force --sign - build/DerivedData/Build/Products/Release/SIDPLAY.app/Contents/PlugIns/SIDTuneViewer.appex
codesign --force --sign - build/DerivedData/Build/Products/Release/SIDPLAY.app/Contents/Frameworks/*
codesign --force --sign - build/DerivedData/Build/Products/Release/SIDPLAY.app/Contents/MacOS/psid64
codesign --force --sign - build/DerivedData/Build/Products/Release/SIDPLAY.app/Contents/Library/Spotlight/SIDMusic.mdimporter
codesign --force --sign - build/DerivedData/Build/Products/Release/SIDPLAY.app
```

If Gatekeeper blocks the app, clear quarantine for local use:
```
xattr -dr com.apple.quarantine build/DerivedData/Build/Products/Release/SIDPLAY.app
```

## developer ID signing (distribution)
Use Xcode archive/export if you have a Developer ID certificate:
```
xcodebuild -project SIDPLAY.xcodeproj -scheme SIDPLAY -configuration Release archive -archivePath build/SIDPLAY.xcarchive
xcodebuild -exportArchive -archivePath build/SIDPLAY.xcarchive -exportOptionsPlist /path/to/ExportOptions.plist -exportPath build/export
```
