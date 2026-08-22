import { A, useSearchParams } from "@solidjs/router";
import { For, Show, createEffect, createResource, createSignal } from "solid-js";
import { getMailingLists, getThreads, threadRoute } from "../api";
import { absoluteDate, displayAuthor, displaySubject, plural } from "../format";
import type {
  MailingListResponse,
  PatchSeries,
  ThreadListResponse,
  ThreadSummary,
} from "../types";

function firstParameter(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "The request failed";
}

function patchLabel(patchSeries: readonly PatchSeries[]): string | undefined {
  const patch = patchSeries[0];
  if (!patch) {
    return undefined;
  }

  const parts =
    patch.receivedParts === patch.totalParts
      ? `${patch.totalParts} parts`
      : `${patch.receivedParts}/${patch.totalParts} parts`;
  return `${patch.status} · ${parts}`;
}

function ThreadRow(props: { thread: ThreadSummary }) {
  const thread = () => props.thread;

  return (
    <li class="thread-row">
      <div class="thread-title-line">
        <A href={threadRoute(thread().rootMessageId)}>{displaySubject(thread().subject)}</A>
        {/*<span class={`kind-badge kind-${thread().kind}`}>
          {thread().kind === "patch-series" ? "patch series" : "discussion"}
        </span>*/}
      </div>
      <div class="thread-meta">
        <span>{displayAuthor(thread().author)}</span>
        <Show when={thread().startedAt}>
          {(startedAt) => (
            <span>created {absoluteDate(startedAt())}</span>
          )}
        </Show>
        <span>updated {absoluteDate(thread().lastActivityAt)}</span>
        <span>{plural(thread().messageCount, "message")}</span>
        <For each={thread().mailingLists}>
          {(mailingList) => (
            <span class="meta-tag" title={mailingList.name}>
              {mailingList.archiveGroup}
            </span>
          )}
        </For>
        <For each={thread().subsystems}>
          {(subsystem) => <span class="meta-tag">{subsystem.name}</span>}
        </For>
      </div>
    </li>
  );
}

export function ThreadListPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [searchText, setSearchText] = createSignal("");

  createEffect(() => {
    setSearchText(firstParameter(searchParams.q) || "");
  });

  const [mailingLists, { refetch: refetchMailingLists }] =
    createResource<MailingListResponse>(() => getMailingLists());
  const [threads, { refetch: refetchThreads }] = createResource<
    ThreadListResponse,
    { mailingList?: string; q?: string; cursor?: string }
  >(
    () => ({
      mailingList: firstParameter(searchParams.mailingList),
      q: firstParameter(searchParams.q),
      cursor: firstParameter(searchParams.cursor),
    }),
    (parameters) => getThreads(parameters),
  );
  const visibleThreads = () => (threads.error ? undefined : threads());

  const selectMailingList = (event: Event) => {
    const value = (event.currentTarget as HTMLSelectElement).value;
    setSearchParams({
      mailingList: value || undefined,
      cursor: undefined,
    });
  };

  const moveToCursor = (cursor: string | null) => {
    if (cursor) {
      setSearchParams({ cursor });
    }
  };

  const submitSearch = (event: SubmitEvent) => {
    event.preventDefault();
    const q = searchText().trim();
    setSearchParams({
      q: q || undefined,
      cursor: undefined,
    });
  };

  const clearSearch = () => {
    setSearchText("");
    setSearchParams({
      q: undefined,
      cursor: undefined,
    });
  };

  return (
    <section aria-label="Threads">
      <div class="page-heading">
        <select
          class="filter-control"
          aria-label="Filter by mailing list"
          disabled={mailingLists.loading}
          onChange={selectMailingList}
          value={firstParameter(searchParams.mailingList) || ""}
        >
          <option value="">All lists</option>
          <For each={mailingLists()?.items}>
            {(mailingList) => (
              <option value={mailingList.archiveGroup}>{mailingList.archiveGroup}</option>
            )}
          </For>
        </select>
        <form class="search-form" onSubmit={submitSearch}>
          <input
            aria-label="Search threads"
            maxlength={512}
            onInput={(event) => setSearchText(event.currentTarget.value)}
            placeholder='Subject, author:"name", date:YYYY-MM-DD'
            type="search"
            value={searchText()}
          />
          <button type="submit">Search</button>
          <button
            disabled={!searchText() && !firstParameter(searchParams.q)}
            onClick={clearSearch}
            type="button"
          >
            Clear
          </button>
        </form>
      </div>

      <Show when={mailingLists.error}>
        <div class="inline-notice" role="status">
          Mailing-list filters are unavailable. {errorMessage(mailingLists.error)}{" "}
          <button class="text-button" onClick={() => void refetchMailingLists()} type="button">
            Retry
          </button>
        </div>
      </Show>

      <Show when={threads.loading && !threads.latest}>
        <ol class="thread-list" aria-label="Loading threads" aria-busy="true">
          <For each={Array.from({ length: 8 })}>
            {() => (
              <li class="thread-row thread-skeleton">
                <span />
                <span />
              </li>
            )}
          </For>
        </ol>
      </Show>

      <Show when={threads.error}>
        <div class="error-state" role="alert">
          <h2>Could not load threads</h2>
          <p>{errorMessage(threads.error)}</p>
          <button onClick={() => void refetchThreads()} type="button">
            Retry
          </button>
        </div>
      </Show>

      <Show when={visibleThreads()}>
        {(page) => (
          <>
            <Show
              when={page().items.length > 0}
              fallback={<p class="empty-state">No threads match these filters.</p>}
            >
              <ol class="thread-list" aria-live="polite" aria-busy={threads.loading}>
                <For each={page().items}>{(thread) => <ThreadRow thread={thread} />}</For>
              </ol>
            </Show>

            <nav class="pagination" aria-label="Thread pages">
              <button
                disabled={!page().pagination.previousCursor || threads.loading}
                onClick={() => moveToCursor(page().pagination.previousCursor)}
                type="button"
              >
                Previous
              </button>
              <button
                disabled={!page().pagination.nextCursor || threads.loading}
                onClick={() => moveToCursor(page().pagination.nextCursor)}
                type="button"
              >
                Next
              </button>
            </nav>
          </>
        )}
      </Show>
    </section>
  );
}
