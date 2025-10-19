declare module "textract";

declare module "pdf-parse" {
  interface PdfParseResult {
    text: string;
    info?: unknown;
    metadata?: unknown;
    version?: string;
  }
  export default function pdfParse(
    dataBuffer: Buffer|Uint8Array,
    options?: unknown
  ): Promise<PdfParseResult>;
}
