import Box from '@mui/material/Box'
import Typography from '@mui/material/Typography'
import { tokens } from '../theme/tokens.ts'

export function DirectoryUnavailable() {
  return (
    <Box
      sx={{
        p: `${tokens.spaceMd}px`,
        borderRadius: `${tokens.cardRadius}px`,
        border: 1,
        borderColor: 'divider',
        bgcolor: 'background.paper',
      }}
    >
      <Typography component="h2" variant="h5" sx={{ fontWeight: 700, lineHeight: 1.4, mb: 1.5 }}>
        تعذّر فتح دليل المشتركين
      </Typography>
      <Typography sx={{ lineHeight: 1.6 }}>
        عميل الإدارة غير جاهز. أعد تحميل الصفحة.
      </Typography>
    </Box>
  )
}
