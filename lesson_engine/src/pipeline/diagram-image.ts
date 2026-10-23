import sharp from 'sharp';

export interface DiagramBBox {
  x: number;
  y: number;
  width: number;
  height: number;
}

export async function extractDiagramImage(input: Buffer, bbox?: DiagramBBox): Promise<Buffer> {
  const image = sharp(input, { failOn: 'none' });
  const metadata = await image.metadata();
  const width = metadata.width;
  const height = metadata.height;
  if (!width || !height) throw new Error('无法读取题目图片尺寸');

  if (!bbox) {
    return image.resize({ width: 960, height: 580, fit: 'inside', withoutEnlargement: true }).png().toBuffer();
  }

  const left = Math.max(0, Math.min(width - 1, Math.round(bbox.x * width)));
  const top = Math.max(0, Math.min(height - 1, Math.round(bbox.y * height)));
  const cropWidth = Math.max(1, Math.min(width - left, Math.round(bbox.width * width)));
  const cropHeight = Math.max(1, Math.min(height - top, Math.round(bbox.height * height)));

  return image
    .extract({ left, top, width: cropWidth, height: cropHeight })
    .resize({ width: 900, height: 520, fit: 'inside', withoutEnlargement: true })
    .png()
    .toBuffer();
}
