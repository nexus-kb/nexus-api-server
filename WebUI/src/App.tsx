import { A, type RouteSectionProps } from "@solidjs/router";

export function AppShell(props: RouteSectionProps) {
  return (
    <div class="site-shell">
      <header class="site-header">
        <A class="site-title" href="/" end>
          Nexus KB
        </A>
      </header>
      <main id="main-content">{props.children}</main>
    </div>
  );
}
