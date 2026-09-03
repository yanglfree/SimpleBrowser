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
  @Prop tags: string[] = [];
  @Prop highlights: ArticleHighlight[] = [];
  @State private noteBody: string = '';
  @State private topicName: string = '';
  @State private tagName: string = '';
  @State private editingNoteId: string = '';
  @State private operationFailed: boolean = false;
  @State private isSaving: boolean = false;
  onAddNote: (body: string) => Promise<void> = async (): Promise<void> => {};
  onAddTopic: (name: string) => Promise<void> = async (): Promise<void> => {};
  onUpdateTags: (tags: string[]) => void = (_tags: string[]): void => {};
  onAddHighlight: (quote: string) => void = (_quote: string): void => {};
  onEditNote: (id: string, body: string) => Promise<void> = async (): Promise<void> => {};
  onDeleteNote: (id: string) => Promise<void> = async (): Promise<void> => {};
  onDeleteHighlight: (id: string) => Promise<void> = async (): Promise<void> => {};
  onRemoveTopic: (id: string) => Promise<void> = async (): Promise<void> => {};
  onLocateHighlight: (id: string) => void = (): void => {};

  build() {
    Column({ space: 10 }) {
      if (this.operationFailed) {
        Text($r('app.string.article_storage_failed')).fontColor($r('app.color.text_secondary')).fontSize(13)
      }
      Text($r('app.string.article_topics'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.topics.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.topics, (topic: Topic) => {
            Button(`#${topic.name} ×`).fontSize(13).height(36).margin(4)
              .onClick((): void => { void this.perform((): Promise<void> => this.onRemoveTopic(topic.id)); })
          }, (topic: Topic): string => topic.id)
        }
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
          void this.perform(async (): Promise<void> => {
            await this.onAddTopic(this.topicName);
            this.topicName = '';
          });
        })
        .onChange((value: string): void => { this.topicName = value; })

      Text($r('app.string.article_tags'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.tags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.tags, (tag: string) => {
            Text(`#${tag} ×`)
              .fontSize(13)
              .fontColor($r('app.color.accent'))
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .backgroundColor($r('app.color.surface_subtle'))
              .borderRadius(8)
              .margin({ right: 8, bottom: 8 })
              .focusable(true)
              .hoverEffect(HoverEffect.Auto)
              .onClick(() => this.onUpdateTags(this.tags.filter((item: string): boolean => item !== tag)))
          }, (tag: string): string => tag)
        }
        .width('100%')
      }
      TextInput({ text: this.tagName, placeholder: $r('app.string.article_tag_placeholder') })
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_subtle'))
        .borderRadius(10)
        .onSubmit((): void => {
          const tag: string = this.tagName.trim();
          if (tag.length > 0 && !this.tags.includes(tag)) {
            this.onUpdateTags(this.tags.concat([tag]));
          }
          this.tagName = '';
        })
        .onChange((value: string): void => { this.tagName = value; })

      Text($r('app.string.article_notes'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextArea({ text: this.noteBody, placeholder: $r('app.string.article_note_placeholder') })
        .width('100%')
        .height(100)
        .padding({ left: 12, right: 12 })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_subtle'))
        .borderRadius(10)
        .onChange((value: string): void => { this.noteBody = value; })
      Row({ space: 8 }) {
        Button($r('app.string.article_annotation_save')).fontSize(13).height(36)
          .enabled(!this.isSaving && this.noteBody.trim().length > 0)
          .onClick((): void => { void this.saveNote(); })
        if (this.editingNoteId.length > 0) {
          Button($r('app.string.article_annotation_cancel')).fontSize(13).height(36)
            .onClick((): void => { this.editingNoteId = ''; this.noteBody = ''; })
        }
      }
      ForEach(this.notes, (note: ArticleNote) => {
        Text(note.body)
          .fontSize(14)
          .lineHeight(21)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.surface_subtle'))
          .borderRadius(10)
        Row({ space: 8 }) {
          Button($r('app.string.article_annotation_edit')).fontSize(12).height(32)
            .onClick((): void => { this.editingNoteId = note.id; this.noteBody = note.body; })
          Button($r('app.string.article_annotation_delete')).fontSize(12).height(32)
            .onClick((): void => { void this.perform((): Promise<void> => this.onDeleteNote(note.id)); })
        }
      }, (note: ArticleNote): string => note.id)

      Text($r('app.string.article_highlights'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text($r('app.string.article_select_text')).fontSize(13).fontColor($r('app.color.text_secondary'))
      ForEach(this.highlights, (highlight: ArticleHighlight) => {
        Text(`“${highlight.textQuote}”`)
          .fontSize(14)
          .lineHeight(21)
          .fontColor(highlight.state === ArticleHighlightState.Located
            ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.surface_subtle'))
          .borderRadius(10)
          .onClick((): void => this.onLocateHighlight(highlight.id))
        Button($r('app.string.article_annotation_delete')).fontSize(12).height(32)
          .onClick((): void => { void this.perform((): Promise<void> => this.onDeleteHighlight(highlight.id)); })
      }, (highlight: ArticleHighlight): string => highlight.id)
    }
    .width('100%')
  }

  private async saveNote(): Promise<void> {
    this.isSaving = true;
    await this.perform(async (): Promise<void> => {
      if (this.editingNoteId.length > 0) {
        await this.onEditNote(this.editingNoteId, this.noteBody);
      } else {
        await this.onAddNote(this.noteBody);
      }
      this.noteBody = '';
      this.editingNoteId = '';
    });
    this.isSaving = false;
  }

  private async perform(action: () => Promise<void>): Promise<void> {
    this.operationFailed = false;
    try {
      await action();
    } catch (error) {
      this.operationFailed = true;
    }
  }
}
