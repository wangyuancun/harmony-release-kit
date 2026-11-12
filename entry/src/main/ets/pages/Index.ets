/**
 * 最小可编译页面（模板占位）。
 * 换成业务页面时：保留 @Entry + @Component + build()，其余内容整体替换即可。
 */
@Entry
@Component
struct Index {
  @State appName: string = '应用模板';

  build() {
    Column({ space: 12 }) {
      Text(this.appName)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')

      Text('HarmonyOS 应用上架模板')
        .fontSize(14)
        .fontColor('#888888')

      Text('把本页替换为你的第一个业务页面')
        .fontSize(16)
        .fontColor('#333333')
        .margin({ top: 24 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F5F5F5')
  }
}
