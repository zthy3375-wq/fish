import { ref, onMounted, onUnmounted } from "vue";
export type Page = "home" | "academic" | "profile";
const sections = [
  "overview",
  "schedule",
  "grades",
  "exams",
  "study",
  "calendar",
  "official",
];
export function parseRoute(hash: string) {
  const [raw, sub] = hash.replace(/^#\/?/, "").split("/");
  const page: Page = raw === "academic" || raw === "profile" ? raw : "home";
  return {
    page,
    section: page === "academic" && sections.includes(sub) ? sub : "overview",
  };
}
export function useNavigation() {
  const initial = parseRoute(location.hash),
    page = ref<Page>(initial.page),
    section = ref(initial.section),
    overlay = ref("");
  let depth = 0,
    activeUrl = location.href,
    overlayGuard: (() => boolean) | undefined;
  function setOverlayCloseGuard(guard: () => boolean) {
    overlayGuard = guard;
  }
  const apply = () => {
    if (
      overlay.value === "course-editor" &&
      history.state?.campusOverlay !== "course-editor" &&
      overlayGuard &&
      !overlayGuard()
    ) {
      history.pushState(
        { campusDepth: depth, campusOverlay: overlay.value },
        "",
        activeUrl,
      );
      return;
    }
    activeUrl = location.href;
    const r = parseRoute(location.hash);
    page.value = r.page;
    section.value = r.section;
    overlay.value = history.state?.campusOverlay || "";
    depth = history.state?.campusDepth || 0;
  };
  history.replaceState(
    { ...history.state, campusDepth: 0, campusOverlay: "" },
    "",
    location.href,
  );
  function move(p: Page, s = "overview") {
    if (p === page.value && s === section.value && !overlay.value) return;
    if (overlay.value)
      history.replaceState(
        { campusDepth: depth, campusOverlay: "" },
        "",
        `#/${p}${p === "academic" && s !== "overview" ? "/" + s : ""}`,
      );
    else
      history.pushState(
        { campusDepth: ++depth, campusOverlay: "" },
        "",
        `#/${p}${p === "academic" && s !== "overview" ? "/" + s : ""}`,
      );
    activeUrl = location.href;
    page.value = p;
    section.value = s;
    overlay.value = "";
    document.querySelector("main")?.scrollTo(0, 0);
  }
  function open(value: string) {
    if (overlay.value) {
      history.replaceState(
        { ...history.state, campusOverlay: value },
        "",
        location.href,
      );
    } else {
      history.pushState(
        { campusDepth: ++depth, campusOverlay: value },
        "",
        location.href,
      );
    }
    activeUrl = location.href;
    overlay.value = value;
  }
  function back() {
    if (overlay.value) {
      close();
      return;
    }
    if (depth > 0) {
      history.back();
    } else if (overlay.value) {
      overlay.value = "";
    } else if (page.value === "academic" && section.value !== "overview") {
      move("academic");
    } else if (page.value !== "home") {
      move("home");
    }
  }
  function close() {
    if (!overlay.value) return;
    overlay.value = "";
    if (depth > 0) history.back();
    else
      history.replaceState(
        { ...history.state, campusOverlay: "" },
        "",
        location.href,
      );
  }
  onMounted(() => window.addEventListener("popstate", apply));
  onUnmounted(() => window.removeEventListener("popstate", apply));
  return {
    page,
    section,
    overlay,
    move,
    open,
    close,
    back,
    setOverlayCloseGuard,
    canBack: () => depth > 0 || page.value !== "home" || !!overlay.value,
  };
}
