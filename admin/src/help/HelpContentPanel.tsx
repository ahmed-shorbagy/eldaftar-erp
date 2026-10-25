import Alert from '@mui/material/Alert'
import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import Checkbox from '@mui/material/Checkbox'
import FormControlLabel from '@mui/material/FormControlLabel'
import Stack from '@mui/material/Stack'
import TextField from '@mui/material/TextField'
import Typography from '@mui/material/Typography'
import { useCallback, useEffect, useRef, useState } from 'react'
import { tokens } from '../theme/tokens.ts'
import {
  HelpError,
  type HelpGateway,
  type HelpTopicRow,
  type PlatformAnnouncementRow,
} from './HelpGateway.ts'
import { helpCopy } from './copy.ts'

export function HelpContentPanel({
  gateway,
  onAccessLost,
}: {
  gateway: HelpGateway
  onAccessLost?: () => void
}) {
  const [topics, setTopics] = useState<HelpTopicRow[] | null>(null)
  const [announcement, setAnnouncement] = useState<PlatformAnnouncementRow | null>(null)
  const [annDraft, setAnnDraft] = useState({ titleAr: '', bodyAr: '', linkUrl: '' })
  const [loadError, setLoadError] = useState(false)
  const [busy, setBusy] = useState(false)
  const [feedback, setFeedback] = useState<string | null>(null)
  const [newTopicTitle, setNewTopicTitle] = useState('')
  const requestGen = useRef(0)

  const load = useCallback(async () => {
    const gen = ++requestGen.current
    setLoadError(false)
    try {
      const [catalog, ann] = await Promise.all([
        gateway.listCatalog(),
        gateway.getAnnouncement(),
      ])
      if (gen !== requestGen.current) return
      setTopics(catalog)
      setAnnouncement(ann)
      setAnnDraft({
        titleAr: ann.titleAr,
        bodyAr: ann.bodyAr,
        linkUrl: ann.linkUrl ?? '',
      })
    } catch (error) {
      if (gen !== requestGen.current) return
      if (error instanceof HelpError && error.code === 'unauthorized') {
        onAccessLost?.()
        return
      }
      setLoadError(true)
    }
  }, [gateway, onAccessLost])

  useEffect(() => {
    void load()
  }, [load])

  const run = async (action: () => Promise<string>) => {
    if (busy) return
    setBusy(true)
    setFeedback(null)
    const gen = requestGen.current
    try {
      const message = await action()
      if (gen !== requestGen.current) return
      setFeedback(message)
      await load()
    } catch (error) {
      if (gen !== requestGen.current) return
      if (error instanceof HelpError && error.code === 'unauthorized') {
        onAccessLost?.()
        return
      }
      setFeedback(helpCopy.saveError)
    } finally {
      setBusy(false)
    }
  }

  if (loadError && topics === null) {
    return (
      <Alert
        severity="error"
        action={<Button onClick={() => void load()}>{helpCopy.retry}</Button>}
      >
        {helpCopy.loadError}
      </Alert>
    )
  }

  return (
    <Stack spacing={2} sx={{ minWidth: 0 }}>
      <Typography component="h2" variant="h5" sx={{ fontWeight: 700 }}>
        {helpCopy.title}
      </Typography>
      <Typography sx={{ lineHeight: 1.6 }}>{helpCopy.intro}</Typography>
      {feedback && (
        <Alert severity={feedback === helpCopy.saveError ? 'error' : 'success'}>
          {feedback}
        </Alert>
      )}

      <Box
        component="section"
        aria-label={helpCopy.announcementTitle}
        sx={{
          p: 2,
          borderRadius: '16px',
          border: 1,
          borderColor: 'divider',
          bgcolor: 'background.paper',
          display: 'grid',
          gap: `${tokens.spaceMd}px`,
        }}
      >
        <Typography component="h3" variant="h6" sx={{ fontWeight: 700 }}>
          {helpCopy.announcementTitle}
        </Typography>
        <Typography variant="body2" color="text.secondary">
          {announcement?.published ? helpCopy.published : helpCopy.unpublished}
        </Typography>
        <TextField
          label={helpCopy.announcementTitleField}
          value={annDraft.titleAr}
          onChange={(e) => setAnnDraft((d) => ({ ...d, titleAr: e.target.value }))}
          disabled={busy}
        />
        <TextField
          label={helpCopy.announcementBody}
          value={annDraft.bodyAr}
          onChange={(e) => setAnnDraft((d) => ({ ...d, bodyAr: e.target.value }))}
          multiline
          minRows={2}
          disabled={busy}
        />
        <TextField
          label={helpCopy.announcementLink}
          value={annDraft.linkUrl}
          onChange={(e) => setAnnDraft((d) => ({ ...d, linkUrl: e.target.value }))}
          slotProps={{ htmlInput: { dir: 'ltr' } }}
          disabled={busy}
        />
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
          <Button
            variant="contained"
            disabled={busy}
            sx={{ minHeight: 48 }}
            onClick={() =>
              void run(async () => {
                const title = annDraft.titleAr.trim()
                const body = annDraft.bodyAr.trim()
                const link = annDraft.linkUrl.trim() || null
                if (!title || !body) throw new HelpError('invalid')
                if (link !== null && !/^https:\/\//i.test(link)) {
                  throw new HelpError('invalid')
                }
                const result = await gateway.setAnnouncement({
                  titleAr: title,
                  bodyAr: body,
                  linkUrl: link,
                  published: true,
                })
                return result.status === 'unchanged' ? helpCopy.unchanged : helpCopy.saved
              })
            }
          >
            {busy ? helpCopy.saving : helpCopy.saveAnnouncement}
          </Button>
          <Button
            variant="outlined"
            disabled={busy}
            sx={{ minHeight: 48 }}
            onClick={() =>
              void run(async () => {
                await gateway.setAnnouncement({
                  titleAr: '',
                  bodyAr: '',
                  linkUrl: null,
                  published: false,
                })
                return helpCopy.cleared
              })
            }
          >
            {helpCopy.clearAnnouncement}
          </Button>
        </Stack>
      </Box>

      <Typography component="h3" variant="h6" sx={{ fontWeight: 700 }}>
        {helpCopy.topicsTitle}
      </Typography>
      <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
        <TextField
          label={helpCopy.topicTitle}
          value={newTopicTitle}
          onChange={(e) => setNewTopicTitle(e.target.value)}
          disabled={busy}
          fullWidth
        />
        <Button
          variant="contained"
          disabled={busy}
          sx={{ minHeight: 48, minWidth: 160 }}
          onClick={() =>
            void run(async () => {
              const title = newTopicTitle.trim()
              if (!title) throw new HelpError('invalid')
              await gateway.upsertTopic({
                id: null,
                titleAr: title,
                sortOrder: (topics?.length ?? 0) + 1,
                published: true,
              })
              setNewTopicTitle('')
              return helpCopy.saved
            })
          }
        >
          {helpCopy.addTopic}
        </Button>
      </Stack>

      {(topics ?? []).length === 0 && (
        <Typography color="text.secondary">{helpCopy.noTopics}</Typography>
      )}

      {(topics ?? []).map((topic) => (
        <TopicEditor
          key={topic.id}
          topic={topic}
          busy={busy}
          onSaveTopic={(next) =>
            void run(async () => {
              const result = await gateway.upsertTopic(next)
              return result.status === 'unchanged' ? helpCopy.unchanged : helpCopy.saved
            })
          }
          onSaveArticle={(next) =>
            void run(async () => {
              const result = await gateway.upsertArticle(next)
              return result.status === 'unchanged' ? helpCopy.unchanged : helpCopy.saved
            })
          }
        />
      ))}
    </Stack>
  )
}

function TopicEditor({
  topic,
  busy,
  onSaveTopic,
  onSaveArticle,
}: {
  topic: HelpTopicRow
  busy: boolean
  onSaveTopic: (input: {
    id: string | null
    titleAr: string
    sortOrder: number
    published: boolean
  }) => void
  onSaveArticle: (input: {
    id: string | null
    topicId: string
    titleAr: string
    bodyAr: string
    sortOrder: number
    published: boolean
  }) => void
}) {
  const [titleAr, setTitleAr] = useState(topic.titleAr)
  const [published, setPublished] = useState(topic.published)
  const [sortOrder, setSortOrder] = useState(String(topic.sortOrder))
  const [articleTitle, setArticleTitle] = useState('')
  const [articleBody, setArticleBody] = useState('')

  useEffect(() => {
    setTitleAr(topic.titleAr)
    setPublished(topic.published)
    setSortOrder(String(topic.sortOrder))
  }, [topic])

  return (
    <Box
      component="section"
      aria-label={topic.titleAr}
      sx={{
        p: 2,
        borderRadius: '16px',
        border: 1,
        borderColor: 'divider',
        bgcolor: 'background.paper',
        display: 'grid',
        gap: `${tokens.spaceMd}px`,
      }}
    >
      <TextField
        label={helpCopy.topicTitle}
        value={titleAr}
        onChange={(e) => setTitleAr(e.target.value)}
        disabled={busy}
      />
      <TextField
        label={helpCopy.sortOrder}
        value={sortOrder}
        onChange={(e) => setSortOrder(e.target.value)}
        slotProps={{ htmlInput: { dir: 'ltr', inputMode: 'numeric' } }}
        disabled={busy}
      />
      <FormControlLabel
        control={
          <Checkbox
            checked={published}
            onChange={(e) => setPublished(e.target.checked)}
            disabled={busy}
          />
        }
        label={helpCopy.published}
      />
      <Button
        variant="contained"
        disabled={busy}
        sx={{ minHeight: 48 }}
        onClick={() =>
          onSaveTopic({
            id: topic.id,
            titleAr: titleAr.trim(),
            sortOrder: Number.parseInt(sortOrder, 10) || 0,
            published,
          })
        }
      >
        {helpCopy.saveTopic}
      </Button>

      {topic.articles.map((article) => (
        <Typography key={article.id} variant="body2">
          {article.published ? '• ' : `• (${helpCopy.unpublished}) `}
          {article.titleAr}
        </Typography>
      ))}

      <TextField
        label={helpCopy.articleTitle}
        value={articleTitle}
        onChange={(e) => setArticleTitle(e.target.value)}
        disabled={busy}
      />
      <TextField
        label={helpCopy.articleBody}
        value={articleBody}
        onChange={(e) => setArticleBody(e.target.value)}
        multiline
        minRows={2}
        disabled={busy}
      />
      <Button
        variant="outlined"
        disabled={busy}
        sx={{ minHeight: 48 }}
        onClick={() => {
          onSaveArticle({
            id: null,
            topicId: topic.id,
            titleAr: articleTitle.trim(),
            bodyAr: articleBody.trim(),
            sortOrder: topic.articles.length + 1,
            published: true,
          })
          setArticleTitle('')
          setArticleBody('')
        }}
      >
        {helpCopy.addArticle}
      </Button>
    </Box>
  )
}
