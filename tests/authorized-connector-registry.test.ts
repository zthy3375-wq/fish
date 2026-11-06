import { it, expect, vi } from "vitest";
it("ships without a real connector and validates the entire contract before registering", async () => {
  vi.resetModules();
  const registry = await import(
    "../src/services/authorized-connector-registry"
  );
  expect(registry.getAuthorizedAcademicConnector()).toBeNull();
  expect(registry.getAcademicConnectionController()).toBeNull();
  expect(() =>
    registry.registerAuthorizedAcademicConnector({
      id: "ok",
      displayName: "School",
    } as any),
  ).toThrow("契约");
  expect(registry.getAuthorizedAcademicConnector()).toBeNull();
  const valid = {
    id: "school",
    displayName: "School",
    beginOfficialAuthorization: async () => {},
    getSessionStatus: async () => "connected" as const,
    fetchMyAcademicData: async () => ({}),
    disconnect: async () => {},
  };
  registry.registerAuthorizedAcademicConnector(valid);
  expect(registry.getAcademicConnectionController()).not.toBeNull();
  expect(() => registry.registerAuthorizedAcademicConnector(valid)).toThrow(
    "重复",
  );
});
