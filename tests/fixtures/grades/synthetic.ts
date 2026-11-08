import type {SchoolGrade} from '../../../src/services/handan-academic-client';
export const grade=(v:Partial<SchoolGrade>={}):SchoolGrade=>({name:'人工成绩课程',scoreText:'80',credit:2,gpa:3,term:'2025–2026 秋季',kind:'必修',...v});
import fixture from './synthetic.json';
export const syntheticGrades:SchoolGrade[]=fixture;
