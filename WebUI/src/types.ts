export type ThreadKind = "discussion" | "patch-series";
export type MessageAvailability = "available" | "missing";

export interface Pagination {
  previousCursor: string | null;
  nextCursor: string | null;
}

export interface MailingList {
  name: string;
  archiveGroup: string;
}

export interface Subsystem {
  name: string;
  mailingListAddress: string | null;
}

export interface PatchSeries {
  coverLetterMessageId: string | null;
  status: string;
  totalParts: number;
  receivedParts: number;
}

export interface ThreadSummary {
  rootMessageId: string;
  subject: string | null;
  author: string | null;
  startedAt: string | null;
  lastActivityAt: string;
  messageCount: number;
  missingMessageCount: number;
  kind: ThreadKind;
  mailingLists: MailingList[];
  subsystems: Subsystem[];
  patchSeries: PatchSeries[];
}

export interface ThreadListResponse {
  items: ThreadSummary[];
  pagination: Pagination;
}

export type ThreadDetail = ThreadSummary;

export interface PatchPosition {
  partIndex: number;
  totalParts: number;
}

export interface ThreadMessageSummary {
  messageId: string;
  inReplyToMessageId: string | null;
  referenceMessageIds: string[];
  availability: MessageAvailability;
  subject: string | null;
  author: string | null;
  sentAt: string | null;
  bodyPreview: string | null;
  patch: PatchPosition | null;
}

export interface ThreadMessagesResponse {
  rootMessageId: string;
  items: ThreadMessageSummary[];
  pagination: Pagination;
}

export interface Mailbox {
  name: string | null;
  email: string;
}

export interface MessageDetail {
  messageId: string;
  rootMessageId: string;
  inReplyToMessageId: string | null;
  referenceMessageIds: string[];
  availability: MessageAvailability;
  subject: string | null;
  author: string | null;
  to: Mailbox[];
  cc: Mailbox[];
  sentAt: string | null;
  body: string | null;
  patch: PatchPosition | null;
  mailingLists: MailingList[];
  subsystems: Subsystem[];
  loreUrl: string;
}

export interface MailingListResponse {
  items: MailingList[];
}
