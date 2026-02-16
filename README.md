# **WORK**
<img width="1362" height="965" alt="image" src="https://github.com/user-attachments/assets/025a7583-7707-4c6b-8558-9f960c31101e" />

Note: Ensure ~/.local/bin is added to your $PATH in your .bashrc or .zshrc.

## Usage Guide

Run work help at any time for a quick reference.
### Core Tracking

    work start "Project Name" : Starts a standard timer.

    work start "Project" --pomo 50 : Starts a 50-minute Pomodoro session (defaults to 25m if no number is provided).

    work switch "New Project" : Saves the currently running session and immediately starts tracking the new one.

    work stop : Stops the timer, prompts for an optional note, and saves the session.

    work pause / work resume : Pauses or resumes the active timer.

### Analytics & Visuals

    work status : Displays the currently running or paused task.

    work eta : Shows exactly when you will hit your daily hour goal based on today's progress.

    work summary : Displays a breakdown of today's work with a visual progress bar. Can also take arguments like week or month.

    work chart : Displays a 7-day activity bar chart.

    work calendar : Displays a work heatmap for the current month.

### Project & Data Management

    work archive "Project Name" : Moves a project to the archive to declutter your menus.

    work unarchive "Project Name" : Restores an archived project.

    work projects : Lists all active and archived projects with total time spent.

    work edit : Opens your raw CSV log file in your default terminal editor ($EDITOR).

    work undo : Deletes the very last recorded entry in case of a mistake.

    work goal global 8 : Sets your global daily work goal (e.g., 8 hours).

### Data Storage

Work Tracker stores all of its data in your home directory: ~/.worktracker/.

    worklog.csv : Your primary time log.

    .state & .paused : Temporary files holding current session data.

    worklog_*.bak : Rolling automatic backups of your main CSV file.

### License

MIT License

Once that is pushed and looks good on your GitHub page, let me know. We can immediately start building the Daily Timeline view (work day)!
