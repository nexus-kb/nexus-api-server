import { A, useSearchParams } from "@solidjs/router";
import {
  For,
  Show,
  createEffect,
  createMemo,
  createResource,
  createSignal,
  onCleanup,
} from "solid-js";
import {
  getThread,
  getThreadMessages,
  getThreadPatchLineages,
  threadRoute,
} from "../api";
import { absoluteDate, displayAuthor, displaySubject, plural, relativeDate } from "../format";
import { buildThreadTree, mergeMessages, type ThreadTreeNode } from "../threadTree";
import type { MessageDetail } from "../types";

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "The request failed";
}

function firstParameter(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function mailboxList(mailboxes: MessageDetail["to"]): string {
  return mailboxes
    .map((mailbox) => (mailbox.name ? `${mailbox.name} <${mailbox.email}>` : mailbox.email))
    .join(", ");
}

function revisionLabel(
  phase: "RFC" | "PATCH",
  revision: number,
  revisionExplicit: boolean,
  isResend: boolean,
): string {
  const version = revisionExplicit || revision > 1 ? " v" + revision : "";
  const resend = isResend ? " RESEND" : "";
  return phase + version + resend;
}

interface MessageNodeProps {
  node: ThreadTreeNode;
  depth: number;
  expanded: (messageID: string) => boolean;
  toggle: (message: MessageDetail) => void;
}

function MessageNode(props: MessageNodeProps) {
  const message = () => props.node.message;
  const isExpanded = () => props.expanded(message().messageId);

  return (
    <li
      class="message-node"
      classList={{ "message-nested": props.depth > 0 && props.depth <= 10 }}
    >
      <article
        classList={{ "message-missing": message().availability === "missing" }}
        data-message-id={message().messageId}
      >
        <Show
          when={message().availability === "available"}
          fallback={
            <div class="message-summary">
              <div class="message-header">
                <span class="message-author">{displayAuthor(message().author)}</span>
              </div>
              <Show when={message().subject}>
                <div class="message-subject">{displaySubject(message().subject)}</div>
              </Show>
            </div>
          }
        >
          <button
            aria-expanded={isExpanded()}
            aria-label={`${isExpanded() ? "Collapse" : "Expand"} message from ${displayAuthor(message().author)}: ${displaySubject(message().subject)}`}
            class="message-summary"
            onClick={() => props.toggle(message())}
            type="button"
          >
            <div class="message-header">
              <span class="message-author">{displayAuthor(message().author)}</span>
              <Show when={isExpanded()}>
                <span title={absoluteDate(message().sentAt)}>{relativeDate(message().sentAt)}</span>
              </Show>
            </div>
            <Show when={message().subject}>
              <div class="message-subject">{displaySubject(message().subject)}</div>
            </Show>
          </button>
        </Show>

        <Show
          when={message().availability === "available" && isExpanded()}
        >
          <div class="message-recipients">
            <Show when={message().to.length > 0}>
              <div>
                <span>to</span> {mailboxList(message().to)}
              </div>
            </Show>
            <Show when={message().cc.length > 0}>
              <div>
                <span>cc</span> {mailboxList(message().cc)}
              </div>
            </Show>
          </div>
          <pre class="message-body">{message().body || "(empty message body)"}</pre>
          <a class="lore-link" href={message().loreUrl} rel="noreferrer" target="_blank">
            View on lore.kernel.org
          </a>
        </Show>
      </article>

      <Show when={props.node.children.length > 0}>
        <ol class="message-children">
          <For each={props.node.children}>
            {(child) => <MessageNode {...props} depth={props.depth + 1} node={child} />}
          </For>
        </ol>
      </Show>
    </li>
  );
}

export function ThreadPage() {
  const [searchParams] = useSearchParams();
  const rootMessageID = () => firstParameter(searchParams.root)?.trim() || undefined;
  const [pageData, { refetch }] = createResource(rootMessageID, async (root) => {
    const [thread, messagePage] = await Promise.all([
      getThread(root),
      getThreadMessages(root),
    ]);
    return { thread, messagePage };
  });
  const [lineagePage] = createResource(
    rootMessageID,
    async (root) => getThreadPatchLineages(root),
  );
  const [messages, setMessages] = createSignal<MessageDetail[]>([]);
  const [nextCursor, setNextCursor] = createSignal<string | null>(null);
  const [loadingMore, setLoadingMore] = createSignal(false);
  const [loadMoreError, setLoadMoreError] = createSignal<string>();
  const [expandedIDs, setExpandedIDs] = createSignal<ReadonlySet<string>>(new Set());
  let messageTree!: HTMLOListElement;

  createEffect(() => {
    const value = pageData();
    if (value) {
      setMessages(value.messagePage.items);
      setNextCursor(value.messagePage.pagination.nextCursor);
      setLoadMoreError(undefined);
      setExpandedIDs(new Set<string>());
    }
  });

  const tree = createMemo(() => buildThreadTree(messages()));
  const isExpanded = (messageID: string) => expandedIDs().has(messageID);
  const toggleMessage = (message: MessageDetail) => {
    const messageID = message.messageId;
    setExpandedIDs((current) => {
      const next = new Set(current);
      if (next.has(messageID)) {
        next.delete(messageID);
      } else {
        next.add(messageID);
      }
      return next;
    });
  };

  createEffect(() => {
    const currentMessages = messages();
    let cancelled = false;
    queueMicrotask(() => {
      if (cancelled || !messageTree?.isConnected) {
        return;
      }

      const messagesByID = new Map(
        currentMessages.map((message) => [message.messageId, message]),
      );
      const messageElements = Array.from(
        messageTree.querySelectorAll<HTMLElement>("[data-message-id]"),
      );

      const visibleMessageIDs = new Set<string>();

      for (const element of messageElements) {
        if (cancelled || !messageTree?.isConnected) {
          return;
        }

        const message = messagesByID.get(element.dataset.messageId || "");
        if (!message || message.availability !== "available") {
          continue;
        }

        const bounds = element.getBoundingClientRect();
        if (bounds.bottom < 0) {
          continue;
        }
        if (bounds.top >= window.innerHeight) {
          break;
        }

        visibleMessageIDs.add(message.messageId);
      }

      if (visibleMessageIDs.size > 0) {
        setExpandedIDs((current) =>
          new Set([...current, ...visibleMessageIDs]),
        );
      }
    });
    onCleanup(() => {
      cancelled = true;
    });
  });

  const loadMore = async () => {
    const root = rootMessageID();
    const cursor = nextCursor();
    if (!root || !cursor || loadingMore()) {
      return;
    }

    setLoadingMore(true);
    setLoadMoreError(undefined);
    try {
      const page = await getThreadMessages(root, cursor);
      setMessages((current) => mergeMessages(current, page.items));
      setNextCursor(page.pagination.nextCursor);
    } catch (error) {
      setLoadMoreError(errorMessage(error));
    } finally {
      setLoadingMore(false);
    }
  };

  return (
    <section aria-labelledby="thread-heading">
      <nav class="back-link" aria-label="Breadcrumb">
        <A href="/">← Threads</A>
      </nav>

      <Show when={!rootMessageID()}>
        <div class="error-state" role="alert">
          <h1 id="thread-heading">No thread selected</h1>
          <p>The thread URL does not contain a root message ID.</p>
        </div>
      </Show>

      <Show when={rootMessageID() && pageData.loading}>
        <div class="thread-page-skeleton" aria-busy="true" aria-label="Loading thread">
          <span />
          <span />
          <span />
        </div>
      </Show>

      <Show when={pageData.error}>
        <div class="error-state" role="alert">
          <h1 id="thread-heading">Could not load thread</h1>
          <p>{errorMessage(pageData.error)}</p>
          <button onClick={() => void refetch()} type="button">
            Retry
          </button>
        </div>
      </Show>

      <Show when={pageData()}>
        {(data) => (
          <>
            <Show when={lineagePage()}>
              {(page) => (
                <For each={page().items}>
                  {(lineage) => (
                    <section class="lineage-summary" aria-label="Patch lineage">
                      <div class="lineage-eyebrow">
                        Patch lineage · {plural(lineage.revisions.length, "version")}
                      </div>
                      <h1>{lineage.subject}</h1>
                      <nav class="lineage-revisions" aria-label="Patch versions">
                        <For each={lineage.revisions}>
                          {(revision) => (
                            <A
                              class="lineage-revision"
                              classList={{
                                active: revision.rootMessageId === rootMessageID(),
                              }}
                              href={threadRoute(revision.rootMessageId)}
                            >
                              {revisionLabel(
                                revision.phase,
                                revision.revision,
                                revision.revisionExplicit,
                                revision.isResend,
                              )}
                            </A>
                          )}
                        </For>
                      </nav>
                    </section>
                  )}
                </For>
              )}
            </Show>

            <header class="thread-heading">
              <h1 id="thread-heading">{displaySubject(data().thread.subject)}</h1>
              <div class="thread-detail-meta">
                <span>{displayAuthor(data().thread.author)}</span>
                <Show when={data().thread.startedAt}>
                  <span title={absoluteDate(data().thread.startedAt)}>
                    started {relativeDate(data().thread.startedAt)}
                  </span>
                </Show>
                <span title={absoluteDate(data().thread.lastActivityAt)}>
                  active {relativeDate(data().thread.lastActivityAt)}
                </span>
                <span>{plural(data().thread.messageCount, "message")}</span>
              </div>
              <div class="thread-tags">
                <For each={data().thread.mailingLists}>
                  {(mailingList) => <span class="meta-tag">{mailingList.name}</span>}
                </For>
                <For each={data().thread.subsystems}>
                  {(subsystem) => <span class="meta-tag">{subsystem.name}</span>}
                </For>
                <Show when={data().thread.missingMessageCount > 0}>
                  <span class="warning-text">
                    {plural(data().thread.missingMessageCount, "missing message")}
                  </span>
                </Show>
              </div>
            </header>

            <Show
              when={tree().length > 0}
              fallback={<p class="empty-state">This thread has no messages.</p>}
            >
              <ol class="message-tree" aria-live="polite" ref={messageTree}>
                <For each={tree()}>
                  {(node) => (
                    <MessageNode
                      depth={0}
                      expanded={isExpanded}
                      node={node}
                      toggle={toggleMessage}
                    />
                  )}
                </For>
              </ol>
            </Show>

            <Show when={loadMoreError()}>
              {(message) => (
                <div class="inline-error load-more-error" role="alert">
                  {message()}
                </div>
              )}
            </Show>
            <Show when={nextCursor()}>
              <div class="load-more">
                <button disabled={loadingMore()} onClick={() => void loadMore()} type="button">
                  {loadingMore() ? "Loading…" : "Load more messages"}
                </button>
              </div>
            </Show>
          </>
        )}
      </Show>
    </section>
  );
}
