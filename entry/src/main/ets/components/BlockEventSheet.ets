import { BlockCategory, BlockEngine, BlockEvent } from '../models/BlockEventModels';
import { AppIcon, IconName } from './AppIcon';

@Component
export struct BlockEventSheet {
  @Prop events: BlockEvent[] = [];
  onDismiss: () => void = (): void => {};

  build() {
    Column() {
      Row({ space: 12 }) {
        AppIcon({ name: IconName.ArrowLeft, glyphSize: 21, color: $r('app.color.text_primary') })
          .onClick(() => this.onDismiss())
        Text($r('app.string.block_event_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(62)
      .padding({ left: 24, right: 24 })
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })

      if (this.events.length === 0) {
        Column({ space: 10 }) {
          AppIcon({ name: IconName.ShieldCheck, glyphSize: 28, color: $r('app.color.text_secondary') })
          Text($r('app.string.block_event_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.events, (event: BlockEvent) => {
            ListItem() {
              this.EventRow(event)
            }
          }, (event: BlockEvent): string => event.id)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private EventRow(event: BlockEvent) {
    Column({ space: 5 }) {
      Row({ space: 8 }) {
        Text(this.categoryLabel(event.category))
          .fontSize(12)
          .fontColor($r('app.color.accent'))
        Text(this.engineLabel(event.engine))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Text(event.resourceHost.length > 0 ? event.resourceHost : event.resourceUrl)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (event.engine === BlockEngine.OwnRuleEngine && event.ruleSource.length > 0) {
        Text(event.ruleSource)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      } else {
        Text($r('app.string.block_event_system_rule_note'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 14, bottom: 14 })
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
  }

  private categoryLabel(category: BlockCategory): Resource {
    if (category === BlockCategory.Tracker) {
      return $r('app.string.category_trackers');
    }
    if (category === BlockCategory.Other) {
      return $r('app.string.block_event_category_other');
    }
    return $r('app.string.category_ads');
  }

  private engineLabel(engine: BlockEngine): Resource {
    return engine === BlockEngine.OwnRuleEngine
      ? $r('app.string.block_event_engine_own')
      : $r('app.string.block_event_engine_system');
  }
}
