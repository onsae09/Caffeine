<img src="https://github.caffeine-app.net/assets/icon.png" alt="Icon" width="239"/>

# Caffeine
### Don't let your Mac fall asleep.

> **이 저장소는 [domzilla/Caffeine](https://github.com/domzilla/Caffeine)의 포크입니다.** 원본에 아래 변경 사항이 추가되었습니다.

## 포크 변경 사항

### Super Caffeine — 덮개를 닫아도 잠자기 안 함

메뉴바 아이콘을 클릭하면 세 단계를 순환합니다.

| 상태 | 아이콘 | 동작 |
| --- | --- | --- |
| 꺼짐 | 빈 컵 | 평소처럼 잠자기 |
| 켜짐 | 찬 컵 | 자동 잠자기·화면 꺼짐 방지 (원본 동작) |
| **Super** | 찬 컵 + **노란 커피** | 위 동작 + **덮개를 닫아도 잠자기 안 함** (`pmset -a disablesleep 1`) |

- Super를 끄거나, 앱을 종료하거나, 설정한 시간이 끝나면 `pmset -a disablesleep 0`으로 되돌립니다.
- 앱 시작 시 시스템에 이미 `SleepDisabled 1`이 설정되어 있으면 Super 상태로 시작합니다.
- 우클릭 메뉴의 **Super Caffeine (덮개를 닫아도 유지)** 항목으로도 켜고 끌 수 있습니다.
- **배터리 보호**: 전원 연결 없이 배터리가 설정한 값(기본 **20%**) 이하가 되면 Super를 자동으로 끄고 일반 켜짐 상태로 돌아갑니다. 이 상태에서는 Super를 켤 수 없습니다. 기준값은 환경설정에서 10~50% 또는 "안 함"으로 바꿀 수 있습니다.
- `pmset`은 root 권한이 필요하며, 비밀번호 없는 `sudo -n`으로만 실행합니다. 덮개를 닫았을 때, 잠자기 직전, 종료할 때 비밀번호 창이 뜨면 아무도 답할 수 없어 `SleepDisabled 1`이 남을 수 있기 때문입니다. 따라서 아래 sudoers 설정이 **필수**입니다. 설정이 없으면 Super를 켤 때 설정 명령을 안내하는 창(명령 복사 버튼 포함)이 뜹니다.

#### sudoers 설정 (필수)

아래 두 명령만 비밀번호 없이 허용하는 sudoers 규칙을 한 번 추가하세요.

```sh
echo "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > /tmp/caffeine-sudoers
visudo -c -f /tmp/caffeine-sudoers && sudo install -m 0440 -o root -g wheel /tmp/caffeine-sudoers /etc/sudoers.d/caffeine
```

제거하려면 `sudo rm /etc/sudoers.d/caffeine`를 실행하세요.

> ⚠️ 덮개를 닫은 채 가방에 넣으면 발열과 배터리 소모가 커질 수 있습니다. 필요할 때만 사용하세요. 앱이 강제 종료되면 `SleepDisabled 1`이 남을 수 있으니, 그럴 땐 앱을 다시 실행하거나 `sudo pmset -a disablesleep 0`을 실행하세요.

### 기타 변경

- **App Sandbox 비활성화**: 샌드박스 안에서는 `pmset`을 관리자 권한으로 실행할 수 없기 때문입니다. 따라서 App Store 배포용이 아닙니다.
- **자동 업데이트(Sparkle) 제거**: 원본 업데이트가 이 포크를 덮어쓰지 않도록 Sparkle 패키지와 "업데이트 확인..." 메뉴를 제거했습니다.
- **로컬 서명**: "Sign to Run Locally"(ad-hoc)로 빌드하도록 바꾸고 Hardened Runtime을 껐습니다. ad-hoc 서명으로는 Hardened Runtime의 라이브러리 검증을 통과할 수 없어 앱이 바로 종료되기 때문입니다.
- 새 문구는 13개 언어 모두 번역했습니다.

### 빌드 및 설치

```sh
xcodebuild -project src/Caffeine.xcodeproj -scheme Caffeine -configuration Release \
  -destination "platform=macOS" -derivedDataPath build build
rm -rf /Applications/Caffeine.app
ditto build/Build/Products/Release/Caffeine.app /Applications/Caffeine.app
open /Applications/Caffeine.app
```

---

## 원본 README

Caffeine is a tiny program that keeps your Mac awake, useful for ensuring that long running tasks aren't interrupted by your computer going to sleep.

### Installation

Download Caffeine at https://caffeine-app.net and drag it into your Applications folder, then double-click the icon to launch it.

### Usage

Caffeine puts a coffee cup icon in the right side of your menu bar. Click the cup to toggle whether Caffeine is active or not -- a full cup means Caffeine will prevent your Mac from automatically going to sleep, dimming the screen or starting screen savers. An empty cup means your Mac will sleep normally.

<img src="https://github.caffeine-app.net/assets/menubar.png" alt="Menubar" width="277"/>

For more control, right-click (or ⌘-click) the icon to show the menu. From here, you can access the preferences window or set a timeout if you only need Caffeine to prevent sleep for a little while.

<img src="https://github.caffeine-app.net/assets/menu.png" alt="Menu" width="293"/>

Caffeine is intended to be simple, yet powerful. Options you can configure include whether to start Caffeine automatically every time you start up your Mac, whether Caffeine should activate every time it starts, and a default duration if you always want Caffeine to turn itself off after a set time.

<img src="https://github.caffeine-app.net/assets/preferences.png" alt="Preferences" width="645"/>

### FAQ

##### Is this the same Caffeine that I've used before?

Yes! Tomas Franzén of Lighthead Software originally developed Caffeine in 2006, and it has been a well known and loved utility for Mac users for many years. Its simplicity has allowed it to continue working perfectly long after active development had ceased.

In 2018, Michael Jones (IntelliScape Computer Solutions) reached out to Tomas to inquire if they could continue development of Caffeine.

Tomas has graciously provided the source code under an open source license, allowing IntelliScape Computer Solutions to continue developing Caffeine where he left off.

##### Does this work with macOS 10.x?

No, this version requires at least macOS 11 (Big Sur). Caffeine for macOS Yosemite or later (including Catalina) is available at: https://www.intelliscapesolutions.com/apps/caffeine/

##### How is Caffeine different or better than alternatives (such as Amphetamine, KeepingYouAwake, etc)?

Due to the long period of inactivity for Caffeine, a lot of different and great options have been developed. While the alternatives are great apps and definitely worth your consideration, we believe that Caffeine's power lies in its simplicity and ease of use.

### Support

If you have questions, comments or other feedback get in touch at https://caffeine-app.net/support.