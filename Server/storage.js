//
//  storage.js
//  Myaow Relay Server - Hybrid Media Storage Provider (Local Disk + Cloudflare R2 / S3)
//

const fs = require('fs');
const path = require('path');
require('dotenv').config();

const UPLOADS_DIR = process.env.MYAOW_UPLOADS_DIR || path.join(__dirname, 'uploads');
if (!fs.existsSync(UPLOADS_DIR)) {
    fs.mkdirSync(UPLOADS_DIR, { recursive: true });
}

const isR2Configured = Boolean(
    process.env.R2_ACCOUNT_ID &&
    process.env.R2_ACCESS_KEY_ID &&
    process.env.R2_SECRET_ACCESS_KEY &&
    process.env.R2_BUCKET_NAME
);

let s3Client = null;
let S3Commands = null;

if (isR2Configured) {
    try {
        const { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } = require('@aws-sdk/client-s3');
        s3Client = new S3Client({
            region: 'auto',
            endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
            credentials: {
                accessKeyId: process.env.R2_ACCESS_KEY_ID,
                secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
            },
        });
        S3Commands = { PutObjectCommand, GetObjectCommand, DeleteObjectCommand };
        console.log(`📦 [Storage] Cloudflare R2 Activo ☁️ (Bucket: ${process.env.R2_BUCKET_NAME})`);
    } catch (err) {
        console.warn(`⚠️ [Storage] Error inicializando SDK de Cloudflare R2: ${err.message}. Usando almacenamiento local.`);
    }
} else {
    console.log(`📦 [Storage] Almacenamiento Local Activo 📁 (carpeta ./uploads). Para activar Cloudflare R2 sin costo de ancho de banda, configura .env`);
}

/**
 * Sube un archivo a Cloudflare R2 o a disco local según la configuración activa.
 * @param {Object} options
 * @param {Buffer} options.buffer - Contenido binario del archivo
 * @param {string} options.fileName - Nombre del archivo final (ej: uuid.jpg)
 * @param {string} options.contentType - Tipo MIME (ej: image/jpeg, audio/m4a)
 * @returns {Promise<{ mediaId: string, mediaUrl: string }>}
 */
async function uploadFile({ buffer, fileName, contentType = 'application/octet-stream' }) {
    if (isR2Configured && s3Client && S3Commands) {
        try {
            const command = new S3Commands.PutObjectCommand({
                Bucket: process.env.R2_BUCKET_NAME,
                Key: fileName,
                Body: buffer,
                ContentType: contentType,
            });
            await s3Client.send(command);

            // Si hay un dominio público o custom CDN configurado (ej: https://media.myaow.app o https://pub-xxx.r2.dev)
            if (process.env.R2_PUBLIC_URL) {
                const cleanBase = process.env.R2_PUBLIC_URL.replace(/\/+$/, '');
                return {
                    mediaId: fileName,
                    mediaUrl: `${cleanBase}/${fileName}`,
                };
            }

            // Fallback a URL servida por el relay
            return {
                mediaId: fileName,
                mediaUrl: `/api/v1/media/${fileName}`,
            };
        } catch (err) {
            console.error(`❌ [Storage R2] Error subiendo a R2 (${err.message}). Guardando copia local como respaldo...`);
        }
    }

    // Almacenamiento local en disco
    const filePath = path.join(UPLOADS_DIR, fileName);
    await fs.promises.writeFile(filePath, buffer);

    return {
        mediaId: fileName,
        mediaUrl: `/api/v1/media/${fileName}`,
    };
}

/**
 * Obtiene el archivo o stream para servirlo si es solicitado por GET /api/v1/media/:id
 * @param {string} fileName
 * @returns {Promise<{ stream?: any, size?: number, notFound: boolean }>}
 */
async function getFile(fileName) {
    const localPath = path.join(UPLOADS_DIR, fileName);
    if (fs.existsSync(localPath)) {
        const stat = fs.statSync(localPath);
        return {
            stream: fs.createReadStream(localPath),
            size: stat.size,
            notFound: false,
        };
    }

    if (isR2Configured && s3Client && S3Commands) {
        try {
            const command = new S3Commands.GetObjectCommand({
                Bucket: process.env.R2_BUCKET_NAME,
                Key: fileName,
            });
            const response = await s3Client.send(command);
            return {
                stream: response.Body,
                size: response.ContentLength,
                notFound: false,
            };
        } catch (err) {
            return { notFound: true };
        }
    }

    return { notFound: true };
}

module.exports = {
    UPLOADS_DIR,
    isR2Configured,
    uploadFile,
    getFile,
};
