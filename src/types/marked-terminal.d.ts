declare module "marked-terminal" {
  import type { MarkedExtension } from "marked";

  interface MarkedTerminalOptions {
    code?: (code: string) => string;
    blockquote?: (text: string) => string;
    html?: (html: string) => string;
    heading?: (text: string, level: number) => string;
    firstHeading?: (text: string, level: number) => string;
    hr?: () => string;
    listitem?: (text: string) => string;
    list?: (body: string, ordered: boolean) => string;
    paragraph?: (text: string) => string;
    table?: (header: string, body: string) => string;
    tablerow?: (content: string) => string;
    tablecell?: (content: string, flags: object) => string;
    strong?: (text: string) => string;
    em?: (text: string) => string;
    codespan?: (code: string) => string;
    br?: () => string;
    del?: (text: string) => string;
    link?: (href: string, title: string, text: string) => string;
    image?: (href: string, title: string, text: string) => string;
    width?: number;
    reflowText?: boolean;
    unescape?: boolean;
    emoji?: boolean;
    tab?: number;
    showSectionPrefix?: boolean;
  }

  export function markedTerminal(
    options?: MarkedTerminalOptions
  ): MarkedExtension;
}

