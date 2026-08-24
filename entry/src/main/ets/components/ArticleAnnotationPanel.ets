import {
  ArticleHighlight,
  ArticleHighlightState,
  ArticleNote,
  Topic
} from '../models/ArticleLibraryModels';

@Component
export struct ArticleAnnotationPanel {
  @Prop notes: ArticleNote[] = [];
  @Prop topics: Topic[] = [];
  @Prop highlights: ArticleHighlight[] = [];
  @State private noteBody: string = '';
  @State private topicName: string = '';
  @State private highlightQuote: string = '';
  onAddNote: (body: string) => void = (_body: string): void => {};
  onAddTopic: (name: string) => void = (_name: string): void => {};
  onAddHighlight: (quote: string) => void = (_quote: string): void => {};

  build() {
    Column({ space: 10 }) {
      Text($r('app.string.article_topics'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.topics.length > 0) {
        Text(this.topics.map((topic: Topic): string => `#${topic.name}`).join('  '))
          .fontSize(13)
          .fontColor($r('app.color.accent'))
          .width('100%')
      }
      TextInput({ text: this.topicName, placeholder: $r('app.string.article_topic_placeholder') })
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_subtle'))
        .borderRadius(10)
        .onSubmit((): void => {
          this.onAddTopic(this.topicName);
          this.topicName = '';
        })
        .onChange((value: string): void => { this.topicName = value; })

      Text($r('app.string.article_notes'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ text: this.noteBody, placeholder: $r('app.string.article_note_placeholder') })
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_subtle'))
        .borderRadius(10)
        .onSubmit((): void => {
          this.onAddNote(this.noteBody);
          this.noteBody = '';
        })
        .onChange((value: string): void => { this.noteBody = value; })
      ForEach(this.notes, (note: ArticleNote) => {
        Text(note.body)
          .fontSize(14)
          .lineHeight(21)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.surface_subtle'))
          .borderRadius(10)
      }, (note: ArticleNote): string => note.id)

      Text($r('app.string.article_highlights'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ text: this.highlightQuote, placeholder: $r('app.string.article_highlight_placeholder') })
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_subtle'))
        .borderRadius(10)
        .onSubmit((): void => {
          this.onAddHighlight(this.highlightQuote);
          this.highlightQuote = '';
        })
        .onChange((value: string): void => { this.highlightQuote = value; })
      ForEach(this.highlights, (highlight: ArticleHighlight) => {
        Text(highlight.state === ArticleHighlightState.Located
          ? `“${highlight.textQuote}”`
          : `${$r('app.string.article_highlight_needs_relocation')} “${highlight.textQuote}”`)
          .fontSize(14)
          .lineHeight(21)
          .fontColor(highlight.state === ArticleHighlightState.Located
            ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.surface_subtle'))
          .borderRadius(10)
      }, (highlight: ArticleHighlight): string => highlight.id)
    }
    .width('100%')
  }
}
