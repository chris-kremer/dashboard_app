export interface Env {
  APP_API_TOKEN: string;
  GOOGLE_SERVICE_ACCOUNT_JSON: string;
  SPREADSHEET_ID: string;
  VERSION?: string;
}

export interface ScheduleItem {
  rowId: string;
  rowNumber: number;
  date: string;
  task: string;
  category: string;
  comment?: string;
  priority?: number;
  estimateMinutes?: number;
  adjustedPriority?: number;
  delay?: string;
  actualMinutes?: number;
  start?: string;
  stop?: string;
  status: "open" | "in_progress" | "done" | "cancelled" | "logged";
}

export interface CaffeineEntry {
  id: string;
  date: string;
  label: string;
  time: string;
}

export interface FoodEntry {
  id: string;
  date: string;
  time: string;
  mealContext: string;
  item: string;
  amount?: string;
  location?: string;
  notes?: string;
  confidence?: string;
}

export interface SleepEntry {
  date: string;
  sleepHours?: number;
  alarmTime?: string;
  oversleptHours?: number;
  sleepStart?: string;
  plannedWake?: string;
  actualWake?: string;
}

export interface FreeTimeEntry {
  id: string;
  date: string;
  label: string;
  durationMinutes?: number;
  time?: string;
  start?: string;
  end?: string;
}

export interface TrackerSnapshot {
  serverTime: string;
  date: string;
  schedule: ScheduleItem[];
  openTasks: ScheduleItem[];
  caffeine: CaffeineEntry[];
  caffeineOptions: string[];
  food: FoodEntry[];
  sleep: SleepEntry | null;
  freeTime: FreeTimeEntry[];
}
