# App Store

Everything the Mac App Store copy of ReCopy needs. Releases are run by Fastlane (`fastlane/Fastfile`):

```bash
bundle install                        # once
scripts/appstore_screenshots.sh       # when the UI changes: fastlane/screenshots/en-US
bundle exec fastlane mac beta         # TestFlight
bundle exec fastlane mac release      # build, upload, listing, "What's New" from CHANGELOG.md, submit for review
bundle exec fastlane mac metadata     # listing only
```

| What | Where |
|------|-------|
| Sandbox entitlements | `AppStore/ReCopy.entitlements` (the lanes build with `APP_STORE` and these) |
| Name, subtitle, description, keywords, promotional text, URLs | `fastlane/metadata/{en-US,id}/` |
| Category, copyright | `fastlane/metadata/*.txt` |
| Notes and contact for App Review | `fastlane/metadata/review_information/` |
| Age rating (4+, nothing applies) | `fastlane/age_rating.json` |
| Screenshots, 1440×900, English for every language | `fastlane/screenshots/en-US`, made by `scripts/appstore_screenshots.sh` |
| "What's New" | the version's section of `CHANGELOG.md`, without bullets ending in `<!-- github-only -->` (GitHub and Homebrew only). Not sent for the first version, which has none. |
| Privacy policy | `AppStore/privacy-policy.md`, to be published at https://recopy.lazycatlabs.com/privacy |

## Set up once, by hand

1. **API key**: App Store Connect › Users and Access › Integrations › Team Keys, role App Manager. Copy
   `fastlane/.env.example` to `fastlane/.env` and fill it in.
2. **App record**: Apps › + › New App, platform macOS, bundle ID `com.lazycatlabs.recopy`, SKU `recopy`.
3. **Privacy policy**: publish `AppStore/privacy-policy.md` at https://recopy.lazycatlabs.com/privacy.
4. **App Privacy**: answer "No, we do not collect data from this app". ReCopy has no servers or analytics; link
   previews are requests from the Mac straight to the copied site, and the vault is in the user's own folder.
5. **Pricing and Availability**: price and countries.
6. **App Review contact**: first name, last name and phone number (the e-mail and notes come from Fastlane).

Export compliance is answered by the build (`ITSAppUsesNonExemptEncryption = NO`: only HTTPS through Apple's APIs).
