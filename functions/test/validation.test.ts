import { describe, expect, it } from "vitest";

import {
  buildSearchTokens,
  commandRequestId,
  normalizeSearchText,
  parseMap,
  safeStorageFileName,
  validateDynamicFormResponses
} from "../src/validation";

describe("validation utilities", () => {
  it("normalizes accents for bounded Firestore search tokens", () => {
    expect(normalizeSearchText("  Reparación Eléctrica  ")).toBe("reparacion electrica");
    const tokens = buildSearchTokens(["Columbia 21"]);
    expect(tokens).toEqual(expect.arrayContaining(["co", "col", "columbia", "21"]));
    expect(tokens.length).toBeLessThanOrEqual(80);
  });

  it("accepts a caller supplied idempotency key", () => {
    expect(commandRequestId({ requestId: "request_1234" })).toBe("request_1234");
  });

  it("rejects unsafe storage file names", () => {
    expect(safeStorageFileName("evidence_01.jpg")).toBe(true);
    expect(safeStorageFileName("../secret.jpg")).toBe(false);
    expect(safeStorageFileName("folder/photo.jpg")).toBe(false);
  });

  it("bounds dynamic form maps", () => {
    expect(parseMap({ question: true }, "responses", 1000, 2)).toEqual({ question: true });
    expect(() => parseMap({ a: 1, b: 2, c: 3 }, "responses", 1000, 2)).toThrow();
  });

  it("validates required dynamic responses and snapshots labels", () => {
    const fields = validateDynamicFormResponses(
      [{ id: "symptom", type: "shortText", label: "Síntoma", required: true }],
      { symptom: "Ruido anormal" }
    );
    expect(fields[0]).toMatchObject({ id: "symptom", label: "Síntoma" });
    expect(() => validateDynamicFormResponses(
      [{ id: "symptom", type: "shortText", label: "Síntoma", required: true }],
      {}
    )).toThrow();
  });

  it("rejects unknown answers and values outside configured limits", () => {
    const fields = [{
      id: "units",
      type: "number",
      label: "Unidades",
      required: false,
      validation: { minimum: 0, maximum: 10 }
    }];
    expect(() => validateDynamicFormResponses(fields, { units: 11 })).toThrow();
    expect(() => validateDynamicFormResponses(fields, { unknown: true })).toThrow();
  });
});
