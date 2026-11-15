import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = {
  title: "Savvy · Advisor workspace",
  description:
    "Advisor earnings, agreements and commercial terms",
};
export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
