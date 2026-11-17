# Releasing PrtSc

Releases are cut by pushing a `vX.Y.Z` tag. `.github/workflows/release.yml` does the rest: archive, sign, build the `.dmg`, sign it for Sparkle, create the GitHub Release, update the Sparkle appcast and bump the Homebrew cask.

Every optional stage turns itself on when its secrets exist, so the pipeline works today (unsigned builds) and gets better as you add secrets. A missing optional secret produces a workflow warning, not a failure.

| Stage | Needs | Without it |
| --- | --- | --- |
| Archive, ad-hoc sign, `.dmg`, GitHub Release | nothing | n/a |
| Developer ID signing | `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_TEAM_ID` | ad-hoc signed ("unsigned build" note in the release) |
| Notarization + stapling | signing secrets **and** an App Store Connect API key or an Apple ID | signed but not notarized |
| Sparkle signature + appcast | `SPARKLE_ED_PRIVATE_KEY` | skipped, installed apps do not see the release |
| Homebrew cask bump | `HOMEBREW_TAP_TOKEN` | skipped |

## One-time setup

### 1. Create the repositories

- `Sheikh566/PrtSc`: this repo.
- `Sheikh566/homebrew-tap`: an empty public repo. The workflow creates `Casks/prtsc.rb` in it. (Homebrew requires the `homebrew-` prefix; users then run `brew tap sheikh566/tap`.)

### 2. Generate the Sparkle EdDSA keys

Sparkle signs updates with an Ed25519 key pair. The tools ship in the Sparkle SPM artifact, which Xcode downloads when it resolves packages:

```sh
xcodebuild -resolvePackageDependencies -project PrtSc.xcodeproj
scripts/sparkle-tool.sh generate_keys     # prints the path to the binary
"$(scripts/sparkle-tool.sh generate_keys)"
```

`generate_keys` stores the private key in your login keychain and prints the **public key**. Run it again at any time to print the public key again.

Put the public key into `PrtSc/Resources/Info.plist`, replacing the placeholder:

```xml
<key>SUPublicEDKey</key>
<string>PASTE_PUBLIC_KEY_HERE</string>
```

Then export the private key for CI and keep a backup somewhere safe (a password manager). If you lose it, existing installs can never update to a build signed with a new key.

```sh
"$(scripts/sparkle-tool.sh generate_keys)" -x /private/tmp/prtsc-sparkle-private-key
# copy the file's contents into the SPARKLE_ED_PRIVATE_KEY secret, then delete the file
rm /private/tmp/prtsc-sparkle-private-key
```

### 3. The updater starts itself

The app already contains the updater: `AppCoordinator` creates the one `SPUStandardUpdaterController` and wires it to "Check for Updates…" and the Settings toggle. It only *starts* when `SUPublicEDKey` in `Info.plist` is not the placeholder (`UpdateSupport.isConfigured`), so there is nothing to change in code: pasting the real key in step 2 is what switches updates on. Until then the menu item is disabled and the app never checks for updates. (`SUFeedURL` is already `https://sheikh566.github.io/PrtSc/appcast.xml`.)

### 4. Enable GitHub Pages for the appcast

The first release that has `SPARKLE_ED_PRIVATE_KEY` set creates the `gh-pages` branch automatically (it contains only `appcast.xml` and `.nojekyll`). After that first run:

1. Repository **Settings > Pages**.
2. Source: **Deploy from a branch**, branch `gh-pages`, folder `/ (root)`.
3. Check that `https://sheikh566.github.io/PrtSc/appcast.xml` loads.

### 5. Add the secrets

Repository **Settings > Secrets and variables > Actions > New repository secret**. All of these are optional; see the table above for what each unlocks.

| Secret | Value |
| --- | --- |
| `SPARKLE_ED_PRIVATE_KEY` | contents of the file written by `generate_keys -x` |
| `HOMEBREW_TAP_TOKEN` | a fine-grained personal access token limited to `Sheikh566/homebrew-tap` with **Contents: Read and write** |
| `DEVELOPER_ID_CERT_P12` | base64 of your "Developer ID Application" certificate exported as `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `DEVELOPER_ID_CERT_PASSWORD` | the password you set when exporting the `.p12` |
| `APPLE_TEAM_ID` | your 10-character team ID |
| `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_P8` | App Store Connect API key (preferred for notarization); `APPLE_API_KEY_P8` is the `.p8` file contents or its base64 |
| `APPLE_ID`, `APPLE_APP_PASSWORD` | alternative to the API key: your Apple ID and an app-specific password (with `APPLE_TEAM_ID`) |

## Cutting a release

1. Make sure `main` is green in CI and `docs/manual-test-checklist.md` has been run against a Release build.
2. Tag and push. The version comes from the tag; the build number is the workflow run number (it only has to increase, and Sparkle compares it).

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

   Tags must look like `vX.Y.Z`. A tag with a suffix (`v0.2.0-beta.1`) makes a GitHub pre-release and skips the appcast and the cask.
3. Watch the **Release** workflow. It produces `PrtSc-X.Y.Z.dmg` on the GitHub Release, adds an item to `appcast.xml` on `gh-pages`, and commits the new version and checksum to `Casks/prtsc.rb` in the tap.
4. Check: `brew update && brew upgrade --cask prtsc` (or install from the tap), and "Check for Updates…" from an older build.

The release scripts also work locally (each prints its usage when run without arguments):

```sh
scripts/build-app.sh 0.1.0 1 /private/tmp/prtsc-out          # archive Release -> PrtSc.app
scripts/sign-app.sh /private/tmp/prtsc-out/PrtSc.app          # ad-hoc; add an identity for Developer ID
scripts/make-dmg.sh /private/tmp/prtsc-out/PrtSc.app /private/tmp/prtsc-out/PrtSc-0.1.0.dmg
scripts/sparkle-sign.sh /private/tmp/prtsc-out/PrtSc-0.1.0.dmg  # uses the key in your keychain
scripts/selftest.sh                                           # offline check of appcast/cask/dmg scripts
```

Re-running the workflow for the same tag replaces the appcast item with the same version, but `gh release create` fails if the release already exists; delete the release first.

## Unsigned builds (no Apple Developer ID yet)

Until the signing secrets exist, builds are ad-hoc signed. That is enough for the app to run, but Gatekeeper does not recognise the developer:

- The GitHub Release notes say "unsigned build".
- Users open it with right-click > **Open**, or approve it in **System Settings > Privacy & Security**.
- The Homebrew cask removes the quarantine flag itself (the `postflight` block, kept only for unsigned builds).
- Screen Recording permission is tied to the code signature. An ad-hoc signature changes with every build, so after an update macOS may ask users to grant Screen Recording again. A stable Developer ID signature fixes this.
- Sparkle updates still work: they are verified with the EdDSA signature, not the Apple signature.

## When you get an Apple Developer ID

1. In your developer account create a **Developer ID Application** certificate; export it from Keychain Access with its private key as a `.p12`.
2. Add `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD` and `APPLE_TEAM_ID`.
3. Create an App Store Connect API key (Users and Access > Integrations > Keys, role Developer) and add the three `APPLE_API_*` secrets, or add `APPLE_ID` and `APPLE_APP_PASSWORD`.
4. Cut the next release. No workflow change is needed: the release is signed with the hardened runtime and a secure timestamp, the app and the `.dmg` are notarized and stapled, the "unsigned build" note disappears, and the cask drops the quarantine `postflight`.
5. Optionally set `DEVELOPMENT_TEAM` in the Xcode project so local builds can use your certificate too.

Because the signing identity changes from ad-hoc to Developer ID once, Sparkle will accept that one update on the strength of the EdDSA signature alone, and Screen Recording will need to be granted once more.

## Troubleshooting

- **`sign_update` not found**: resolve packages first (`xcodebuild -resolvePackageDependencies -project PrtSc.xcodeproj`) or set `SPARKLE_BIN_DIR` to a directory containing the Sparkle tools.
- **Runner has no Xcode 27**: `scripts/select-xcode.sh` fails with a list of installed Xcodes. Use a newer runner image label in `ci.yml` and `release.yml`.
- **Notarization rejected**: the workflow prints the notary log. The usual causes are an unsigned nested binary (check `scripts/sign-app.sh` output) or a missing hardened runtime/timestamp.
- **Appcast shows but updates are refused**: `SUPublicEDKey` in the shipped app must match the key behind `SPARKLE_ED_PRIVATE_KEY`.
