export interface Env {
  APP_API_TOKEN: string;
  ADDON_API_TOKEN: string;
  GOOGLE_SERVICE_ACCOUNT_JSON: string;
  SPREADSHEET_ID: string;
  NUDGE_COORDINATOR: DurableObjectNamespace;
  AI?: Ai;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_PRIVATE_KEY?: string;
  APNS_TOPIC?: string;
  TIME_ZONE?: string;
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
  plannedStart?: string;
  plannedStop?: string;
  lane?: string;
  source?: string;
  sourceId?: string;
  importedAt?: string;
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

export interface TaskSuggestion {
  task: string;
  category?: string;
  comment?: string;
  priority?: number;
  estimateMinutes?: number;
  useCount: number;
  lastUsedDate: string;
}

export interface FoodSuggestion {
  item: string;
  mealContext?: string;
  amount?: string;
  location?: string;
  confidence?: string;
  useCount: number;
  lastUsedDate: string;
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
  taskSuggestions?: TaskSuggestion[];
  foodSuggestions?: FoodSuggestion[];
  sleep: SleepEntry | null;
  freeTime: FreeTimeEntry[];
}
