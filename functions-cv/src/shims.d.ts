// Minimal shims for packages without proper TS types
declare module "textract";

declare module "pdf-parse" {
  // Provide a very light type so TS allows calling the default export
  function pdfParse(
    dataBuffer: Buffer | Uint8Array,
    options?: any
  ): Promise<{ text: string; info?: any; metadata?: any }>;
  export default pdfParse;
}
