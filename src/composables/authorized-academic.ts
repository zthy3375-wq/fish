import { shallowRef, ref, onUnmounted } from "vue";
import { getAcademicConnectionController } from "../services/authorized-connector-registry";
/** App lifetime, rather than connection-page lifetime: expiry/logout clears every view. */
export function useAuthorizedAcademic() {
  const controller = getAcademicConnectionController();
  const snapshot = shallowRef(controller?.snapshot ?? null),
    showOfficial = ref(false);
  const unsubscribe = controller?.subscribe((value) => {
    snapshot.value = value;
    if (!value) showOfficial.value = false;
  });
  onUnmounted(() => unsubscribe?.());
  return {
    snapshot,
    showOfficial,
    async refreshIfReady() {
      if (controller?.state.phase === "ready") await controller.refresh();
    },
  };
}
