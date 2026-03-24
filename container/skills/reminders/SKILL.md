---
name: reminders
description: Create reminders and recurring tasks with inline snooze/done buttons. Use when the user asks for reminders, recurring chores, or maintenance tasks.
---

# Reminders & Task Patterns

## Inline Buttons

Send messages with interactive buttons by using this JSON format as the message text:

```json
{"text": "Your reminder message here", "buttons": [{"text": "Done", "data": "task_done:TASK_ID"}, {"text": "Snooze 30m", "data": "task_snooze:TASK_ID:1800000"}]}
```

Replace `TASK_ID` with the actual task ID. Button `data` formats:
- `task_done:<task_id>` — marks task complete (or reschedules interval tasks from now)
- `task_snooze:<task_id>:<milliseconds>` — reschedules task to fire after the given delay

Common snooze values: 600000 (10min), 1800000 (30min), 3600000 (1h), 86400000 (tomorrow)

## Task Patterns

### One-time reminder with snooze

When the user says "remind me at 2pm to call the dentist":

1. Create the task: `schedule_task` with `schedule_type: "once"`, `schedule_value: "2026-03-24T14:00:00"`
2. Set the prompt to output a JSON button message:
   ```
   Send this exact message: {"text": "Reminder: Call the dentist", "buttons": [{"text": "Done", "data": "task_done:TASK_ID"}, {"text": "Snooze 30m", "data": "task_snooze:TASK_ID:1800000"}, {"text": "Snooze 1h", "data": "task_snooze:TASK_ID:3600000"}]}
   ```

### Recurring chore (fixed schedule)

When the user says "every Sunday remind me to feed the chickens":

1. Create the task: `schedule_task` with `schedule_type: "cron"`, `schedule_value: "0 8 * * 0"`
2. This fires every Sunday at 8am regardless of acknowledgment

Common cron patterns:
- Daily 9am: `0 9 * * *`
- Weekdays 8am: `0 8 * * 1-5`
- Weekly Sunday 8am: `0 8 * * 0`
- Monthly 1st at 9am: `0 9 1 * *`
- Every 2 weeks: use `interval` with `1209600000` (14 days in ms)

### Maintenance task (reschedule from completion)

When the user says "remind me to change air filters every 3 months":

1. Create the task: `schedule_task` with `schedule_type: "interval"`, `schedule_value: "7776000000"` (90 days)
2. Set the prompt to output a JSON button message with a "Mark Done" button:
   ```
   Send this exact message: {"text": "Time to change the air filters!", "buttons": [{"text": "Mark Done", "data": "task_done:TASK_ID"}]}
   ```
3. When the user taps "Mark Done", the system reschedules the task from that moment (not from the original schedule)
4. This prevents pile-up — if overdue, it just stays as one pending reminder

Common intervals: 604800000 (1 week), 2592000000 (30 days), 7776000000 (90 days), 31536000000 (1 year)

## Important

- Task IDs are generated when you call `schedule_task` — include them in the button data
- The prompt field should instruct the agent to send the JSON button message verbatim
- For recurring cron tasks, buttons are optional (the task repeats regardless)
- For interval/maintenance tasks, always include a "Mark Done" button so it reschedules from completion
