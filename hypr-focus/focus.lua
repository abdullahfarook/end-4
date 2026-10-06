-- >>> hypr-focus >>>
-- Don't let windows grab focus on their own activation request: JetBrains modal dialogs
-- (Rider) otherwise ping-pong focus between the main window and dialogs and flicker.
hl.config({ misc = { focus_on_activate = false } })
-- <<< hypr-focus <<<
