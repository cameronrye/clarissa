import { describe, test, expect } from "bun:test";
import { resolve } from "path";
import { validatePathWithinBase, getSecurePaths } from "./security.ts";

describe("Security utilities", () => {
  const base = process.cwd();

  test("validatePathWithinBase allows paths inside base directory", () => {
    const target = "src/tools/security.ts";
    const absolute = validatePathWithinBase(target, base);
    const normalizedBase = resolve(base);

    expect(absolute.startsWith(normalizedBase)).toBe(true);
  });

  test("validatePathWithinBase throws for paths outside base directory", () => {
    const outside = resolve(base, "..", "outside-file.txt");

    expect(() => validatePathWithinBase(outside, base)).toThrow(
      "outside the allowed directory",
    );
  });

  test("getSecurePaths returns relative path for file inside base", () => {
    const target = "src/tools/security.ts";
    const { absolutePath, relativePath } = getSecurePaths(target, base);

    expect(absolutePath.endsWith("src/tools/security.ts")).toBe(true);
    expect(relativePath).toBe("src/tools/security.ts");
  });

  test("getSecurePaths returns '.' when path is base directory", () => {
    const { relativePath } = getSecurePaths(".", base);
    expect(relativePath).toBe(".");
  });
});

