import { AppIcon } from '../components/AppIcon';
import { FULL_SCREEN_FADE } from '../common/UiMotion';
import { bundleManager, common } from '@kit.AbilityKit';
import { AppTheme } from '../common/AppTheme';
import { SettingsRow } from '../components/SettingsRow';
interface PhotoCredit {
  author: string;
  profile: string;
  photo: string;
}

const photoCredits: PhotoCredit[] = [
  {
    author: 'Jorgen Hendriksen',
    profile: 'https://unsplash.com/@jor9en',
    photo: 'https://unsplash.com/photos/fly-agaric-mushroom-on-forest-floor-JzctxsrryrY'
  },
  {
    author: 'Lens by Benji',
    profile: 'https://unsplash.com/@lens_by_benji',
    photo: 'https://unsplash.com/photos/arc-de-triomphe-in-paris-at-sunset-WEKPNhAgvHU'
  },
  {
    author: 'Lawrence Chismorie',
    profile: 'https://unsplash.com/@lawrnsky',
    photo: 'https://unsplash.com/photos/woman-looking-out-of-city-window-budEYISRf-U'
  },
  {
    author: 'Maximilian Bungart',
    profile: 'https://unsplash.com/@hypernature',
    photo: 'https://unsplash.com/photos/tabby-cat-sitting-by-window-8Qj5U-QvaqU'
  },
  {
    author: 'Brayden Law',
    profile: 'https://unsplash.com/@braydenlaw',
    photo: 'https://unsplash.com/photos/staircase-in-modern-white-building-8J5FS_6e-84'
  }
];

const developerLetter: string[] = [
  '亲爱的用户，你好：',
  '欢迎使用「拾光整理·EasyPhoto」。',
  '这个项目开发之初，是我发现我的图库里堆了上万张图片，随手拍的风景、临时传达的照片、有意思的梗图、保存信息的截图……是啊，我们当代人的手机总是被这些照片填满，说重要吧，其实也没用；说不重要吧，又想留个念想：人姑且难以判断照片价值，更何况机器？所以我诞生了让我自己手动进行照片分类处理的想法。',
  '一开始我想用图库，可发现只有缩略图能快速选择，这太难判断照片了：如果用详细大图，分类太慢了。于是我想到了一个经典的照片整理软件——Slidebox，可惜，它是iOS端的，没有原生鸿蒙端。于是我去鸿蒙应用市场寻找类似软件，发现要不操作逻辑怪，要不UI设计丑，于是我萌生了自己写程序的想法。',
  '借助今年大热的VibeCoding，我在GPT6.1-sol的帮助下，完成了程序的开发，前后经历上百轮对话，UI打磨了近一周，才完成了这个版本。项目在 GitHub 公开源码，欢迎提交反馈。',
  '同时我也非常重视软件的审美：我觉得2026年的软件，除了实现功能，最重要的就是视觉体验与人机交互逻辑顺畅。因此整个软件的细节打磨是花了最长时间的，不过还是受限于开发时间仓促，如有不足，请多包涵，欢迎通过 GitHub Issues 提交反馈。',
];

@Entry
@Component
struct About {
  private licenseText: string = "ISC License\n\nCopyright (c) 2026 Lucide Icons and Contributors\n\nPermission to use, copy, modify, and/or distribute this software for any\npurpose with or without fee is hereby granted, provided that the above\ncopyright notice and this permission notice appear in all copies.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\" AND THE AUTHOR DISCLAIMS ALL WARRANTIES\nWITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF\nMERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR\nANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES\nWHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN\nACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF\nOR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.\n\n---\n\nThe following Lucide icons are derived from the Feather project:\n\nairplay, alert-circle, alert-octagon, alert-triangle, aperture, arrow-down-circle, arrow-down-left, arrow-down-right, arrow-down, arrow-left-circle, arrow-left, arrow-right-circle, arrow-right, arrow-up-circle, arrow-up-left, arrow-up-right, arrow-up, at-sign, calendar, cast, check, chevron-down, chevron-left, chevron-right, chevron-up, chevrons-down, chevrons-left, chevrons-right, chevrons-up, circle, clipboard, clock, code, columns, command, compass, corner-down-left, corner-down-right, corner-left-down, corner-left-up, corner-right-down, corner-right-up, corner-up-left, corner-up-right, crosshair, database, divide-circle, divide-square, dollar-sign, download, external-link, feather, frown, hash, headphones, help-circle, info, italic, key, layout, life-buoy, link-2, link, loader, lock, log-in, log-out, maximize, meh, minimize, minimize-2, minus-circle, minus-square, minus, monitor, moon, more-horizontal, more-vertical, move, music, navigation-2, navigation, octagon, pause-circle, percent, plus-circle, plus-square, plus, power, radio, rss, search, server, share, shopping-bag, sidebar, smartphone, smile, square, table-2, tablet, target, terminal, trash-2, trash, triangle, tv, type, upload, x-circle, x-octagon, x-square, x, zoom-in, zoom-out\n\nThe MIT License (MIT) (for the icons listed above)\n\nCopyright (c) 2013-present Cole Bemis\n\nPermission is hereby granted, free of charge, to any person obtaining a copy\nof this software and associated documentation files (the \"Software\"), to deal\nin the Software without restriction, including without limitation the rights\nto use, copy, modify, merge, publish, distribute, sublicense, and/or sell\ncopies of the Software, and to permit persons to whom the Software is\nfurnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all\ncopies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\nIMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\nFITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\nAUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\nLIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\nOUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\nSOFTWARE.\n";
  @State private section: string = '';
  @State private version: string = '';

  aboutToAppear(): void {
    try {
      this.version = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch (_) { this.version = ''; }
  }

  onBackPress(): boolean {
    if (!this.section) { return false; }
    this.section = '';
    return true;
  }
  private async openCreditLink(url: string): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.openLink(url);
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开链接，请稍后重试。' });
    }
  }

  pageTransition() {
    PageTransitionEnter(FULL_SCREEN_FADE).opacity(0)
    PageTransitionExit(FULL_SCREEN_FADE).opacity(0)
  }

  @Builder
  technicalStep(title: string, description: string) {
    Text() {
      Span(title).fontWeight(FontWeight.Bold)
      Span(description)
    }.fontSize(16).lineHeight('26fp').fontColor($r('app.color.text_primary')).width('100%')
  }

  build() {
    Column({ space: 24 }) {
      Row() {
        Button({ type: ButtonType.Circle }) { AppIcon({ source: $r('app.media.lucide_arrow_left'), iconSize: 20 }) }
          .width(48).height(48).padding(0).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 24, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).accessibilityText('返回').onClick(() => { if (!this.onBackPress()) { this.getUIContext().getRouter().back(); } })
        Text(this.section || '关于本应用').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      }.width('100%').padding({ left: 20, right: 20 })
      if (!this.section) {
        Scroll() {
          Column({ space: 24 }) {
            Column({ space: 12 }) {
              Image($r('app.media.easyphoto_icon')).width(88).height(88).borderRadius(20)
                .accessibilityText('拾光整理图标')
              Text(this.version ? '版本 ' + this.version : '版本信息不可用')
                .fontSize(16).fontColor($r('app.color.text_secondary'))
            }.width('100%').padding({ top: 12, bottom: 12 })
            Column() {
              SettingsRow({ title: '开发者的话', icon: $r('app.media.lucide_message_square'), divider: true, activated: () => { this.section = '开发者的话'; } })
              SettingsRow({ title: '技术实现逻辑', icon: $r('app.media.lucide_info'), divider: true,
                activated: () => { this.section = '技术实现逻辑'; } })
              SettingsRow({ title: '开源许可与声明', icon: $r('app.media.lucide_file_text'), divider: true, activated: () => { this.section = '开源许可与声明'; } })
              SettingsRow({ title: '联系我们', icon: $r('app.media.lucide_mail'), activated: () => { this.section = '联系我们'; } })
            }.width('100%').borderRadius(AppTheme.cardRadius).clip(true).backgroundColor($r('app.color.surface'))
          }.width('100%').padding({ left: 20, right: 20 })
        }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .transition(TransitionEffect.opacity(0).animation(FULL_SCREEN_FADE))
      } else if (this.section === '开发者的话') {
        Scroll() {
          Column({ space: 16 }) {
            ForEach(developerLetter, (paragraph: string) => {
              Text(paragraph).fontSize(16).lineHeight('26fp').fontColor($r('app.color.text_primary')).width('100%')
            }, (paragraph: string) => paragraph)
          }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 20, right: 20, bottom: 16 })
        }.width('100%').layoutWeight(1).align(Alignment.Top)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Auto)
          .transition(TransitionEffect.opacity(0).animation(FULL_SCREEN_FADE))
      } else if (this.section === '技术实现逻辑') {
        Scroll() {
          Column({ space: 16 }) {
            Text('拾光整理通过 HarmonyOS 系统图库在设备本地整理照片。分类分三步：')
              .fontSize(16).lineHeight('26fp').fontColor($r('app.color.text_primary')).width('100%')
            this.technicalStep('1. 先标记：', '选定目标相册后，最新一笔分类可以撤销。确认下一笔或结束整理时，应用才创建副本。')
            this.technicalStep('2. 再校验：', '应用检查副本是否完整、是否已进入指定相册。复制或校验失败时，原图留在原处。')
            this.technicalStep('3. 最后回收：', '结束整理时，应用再次核对照片。开启「保留原图」则保留两份，否则将符合条件的原图移入系统回收站。操作结果不明确时，应用保留记录，避免重复操作。')
          }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 20, right: 20, bottom: 16 })
        }.width('100%').layoutWeight(1).align(Alignment.Top)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Auto)
          .transition(TransitionEffect.opacity(0).animation(FULL_SCREEN_FADE))
      } else if (this.section === '联系我们') {
        Text('问题与建议请提交至 GitHub Issues').fontSize(17).fontColor($r('app.color.text_primary')).copyOption(CopyOptions.LocalDevice)
          .width('calc(100% - 40vp)').padding(20).borderRadius(AppTheme.cardRadius).backgroundColor($r('app.color.surface'))
          .transition(TransitionEffect.opacity(0).animation(FULL_SCREEN_FADE))
      } else {
        Scroll() {
          Column({ space: 12 }) {
            Text('Unsplash 示例照片').fontSize(18).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary')).width('100%')
            Text('「整理练习」中的示例照片来自 Unsplash，依据 Unsplash License 使用。感谢摄影师分享作品。')
              .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
            Text('https://unsplash.com/license').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
            ForEach(photoCredits, (credit: PhotoCredit) => {
              Row({ space: 8 }) {
                Button(credit.author).type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).layoutWeight(1).constraintSize({ minHeight: 48 })
                  .fontColor($r('app.color.accent'))
                  .accessibilityText('查看摄影师 ' + credit.author)
                  .onClick(() => { this.openCreditLink(credit.profile); })
                Button('查看原图').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).constraintSize({ minHeight: 48 })
                  .fontColor($r('app.color.accent'))
                  .accessibilityText('查看 ' + credit.author + ' 的原图')
                  .onClick(() => { this.openCreditLink(credit.photo); })
              }.width('100%')
            }, (credit: PhotoCredit) => credit.photo)
            Divider().color($r('app.color.divider')).margin({ top: 8, bottom: 8 })
            Text('Lucide 与 Feather 图标').fontSize(18).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary')).width('100%')
            Text(this.licenseText).fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
          }.width('100%').padding({ left: 20, right: 20 })
        }
          .layoutWeight(1).width('100%').edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).transition(TransitionEffect.opacity(0).animation(FULL_SCREEN_FADE))
      }
    }.padding({ top: 20, bottom: 20 }).width('100%').height('100%').backgroundColor($r('app.color.console_background'))
  }
}
