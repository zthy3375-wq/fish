export interface Course { id: string; courseId?:string; arrangementId?:string; semesterId?:string; notes?:string; name: string; teacher: string; room: string; day: number; start: string; end: string; period: string; weeks: number[]; color: string }
export interface Grade { name: string; credit: number; score: number; term: string; kind: string }
export interface Exam { name: string; date: string; time: string; room: string; seat: string }
export interface AcademicData { courses: Course[]; grades: Grade[]; exams: Exam[]; source: 'mock'|'personal'|'official' }
export function coursesForDay(courses: Course[], day: number, week: number) { return courses.filter(c=>c.day===day && c.weeks.includes(week)).sort((a,b)=>a.start.localeCompare(b.start)); }
export function nextCourse(courses: Course[], time: string) { return courses.find(c=>c.end>time); }
export function weightedAverage(grades: Grade[]) { const credits=grades.reduce((s,g)=>s+g.credit,0); return credits ? grades.reduce((s,g)=>s+g.score*g.credit,0)/credits : 0; }
export function teachingWeek(date: Date, start: Date) { return Math.floor((Date.UTC(date.getFullYear(),date.getMonth(),date.getDate())-Date.UTC(start.getFullYear(),start.getMonth(),start.getDate()))/604800000)+1; }
export function weekDate(week:number, day:number) { const date=new Date(2026,8,7+(week-1)*7+day-1); return `${date.getMonth()+1}/${date.getDate()}`; }
