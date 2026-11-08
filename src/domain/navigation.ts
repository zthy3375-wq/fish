/** App-owned return paths. Tab visits are replacements, never a return stack. */
export type Page = 'home' | 'schedule' | 'tasks' | 'academic' | 'profile' | 'life';
export interface Route { page: Page; section: string }
const sections = ['overview', 'learning', 'agenda', 'schedule', 'grades', 'exams', 'study', 'calendar'];
export function parseRoute(hash: string): Route {
  const [raw, sub] = hash.replace(/^#\/?/, '').split('/');
  if (raw === 'tasks' || (raw === 'academic' && sub === 'agenda')) return {page:'tasks',section:'agenda'};
  if (raw === 'academic' && sub === 'official') return {page:'profile',section:'overview'};
  if (raw === 'schedule' || (raw === 'academic' && sub === 'schedule')) return {page:'schedule', section:'schedule'};
  const page: Page = raw === 'academic' || raw === 'profile' || raw === 'life' ? raw : 'home';
  return {page, section:page === 'academic' && sections.includes(sub) ? sub : 'overview'};
}
export function routeKey(route: Route) { return `${route.page}/${route.section}`; }
export function routeHash(route: Route) { return `#/${route.page}${route.page === 'academic' && route.section !== 'overview' ? '/' + route.section : ''}`; }
export class NavigationStack {
  route: Route;
  parents: Route[] = [];
  overlay = '';
  constructor(initial: Route) {
    this.route = initial;
    if (initial.page === 'academic' && initial.section !== 'overview') this.parents = [{page:'academic', section:'overview'}];
  }
  move(page: Page, section = 'overview') {
    const target = parseRoute(`#/${page}/${section}`);
    if (routeKey(target) === routeKey(this.route)) { this.overlay = ''; return; }
    if (target.page === 'academic' && target.section !== 'overview') this.parents.push({...this.route});
    else this.parents = [];
    this.route = target;
    this.overlay = '';
  }
  back() {
    if (this.overlay) this.overlay = '';
    else this.route = this.parents.pop() ?? {page:'home', section:'overview'};
  }
  canBack() { return !!this.overlay || !!this.parents.length || this.route.page !== 'home'; }
}
