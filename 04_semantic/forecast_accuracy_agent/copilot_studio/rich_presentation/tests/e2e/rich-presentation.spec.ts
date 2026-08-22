import { expect, test } from "@playwright/test";

test("renders a governed KPI and exposes its decision trace", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Forecast Accuracy" })).toBeVisible();

  await page.getByRole("button", { name: /KPI answer/ }).click();
  await expect(page.locator(".kpi-value")).toHaveText("39.6%");
  await page.getByRole("button", { name: "View evidence trail" }).last().click();

  const panel = page.getByRole("complementary", { name: "Evidence trail" });
  await expect(panel).toContainText("SCALAR_MATCH");
  await expect(panel).toContainText("evidence://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
  await expect(panel).toContainText("READY");
});

test("keeps the mobile conversation inside the viewport", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: /Trend view/ }).click();
  await expect(page.getByRole("img", { name: /Forecast Accuracy/ })).toBeVisible();

  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow).toBeLessThanOrEqual(1);
});
