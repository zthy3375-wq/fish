import { ref, onMounted, onUnmounted } from 'vue';
import { NavigationStack, parseRoute, routeHash, type Page } from '../domain/navigation';
export { parseRoute, type Page } from '../domain/navigation';

/** One browser boundary; internal return paths never accumulate tab visits. */
export function useNavigation() {
  const stack = new NavigationStack(parseRoute(location.hash));
  const page = ref(stack.route.page), section = ref(stack.route.section), overlay = ref('');
  let beforeBack: (() => boolean) | undefined;
  let overlayGuard: (() => boolean) | undefined;
  const entry = () => ({campusNavigation:true});
  function publish() {
    page.value = stack.route.page; section.value = stack.route.section; overlay.value = stack.overlay;
    history.replaceState(entry(), '', routeHash(stack.route));
  }
  function back() {
    if(beforeBack?.()) return;
    if (stack.overlay && overlayGuard && !overlayGuard()) return;
    stack.back(); publish();
  }
  function browserBack(event: PopStateEvent) {
    if (event.state?.campusBoundary) {
      if (stack.canBack()) {
        back();
        history.replaceState({campusBoundary:true}, '', routeHash(stack.route));
        history.pushState(entry(), '', routeHash(stack.route));
      } else history.back();
    } else {
      // A forward visit or a new hash restores its own route, not stale tab history.
      const route = parseRoute(location.hash);
      stack.route = route; stack.parents = new NavigationStack(route).parents; stack.overlay = ''; publish();
    }
  }
  onMounted(() => {
    if (!history.state?.campusNavigation) {
      history.replaceState({campusBoundary:true}, '', location.href);
      history.pushState(entry(), '', routeHash(stack.route));
    } else publish();
    history.scrollRestoration = 'manual';
    window.addEventListener('popstate', browserBack);
  });
  onUnmounted(() => window.removeEventListener('popstate', browserBack));
  return {
    page, section, overlay,
    move(p: Page, s = 'overview') { stack.move(p, s); publish(); },
    open(value: string) { stack.overlay = value; publish(); },
    // Explicit completion/cancel bypasses the dirty-editor back guard.
    close() { stack.overlay = ''; publish(); },
    back,
    setOverlayCloseGuard(guard: () => boolean) { overlayGuard = guard; },
    setBeforeBack(guard: () => boolean) { beforeBack = guard; },
    canBack: () => stack.canBack(),
  };
}
