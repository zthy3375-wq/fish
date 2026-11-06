/** Recognize v0.4 school partitions in existing schedules/backups. Do not remove this compatibility rule. */
export function isSchoolPageSemester(id: string) { return id.startsWith('school-page-'); }
