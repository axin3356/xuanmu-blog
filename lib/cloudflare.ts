import { getCloudflareContext } from '@opennextjs/cloudflare'

export async function getAppCloudflareContext() {
  try {
    return await getCloudflareContext({ async: true })
  } catch (error) {
    if (!shouldUseLocalRuntime()) {
      throw error
    }

    return {
      env: await getLocalDevEnv(),
      ctx: {
        waitUntil() {},
        passThroughOnException() {},
        props: {},
      },
      cf: undefined,
      caches: undefined,
    }
  }
}

export async function getAppCloudflareEnv() {
  return (await getAppCloudflareContext()).env
}

async function getLocalDevEnv(): Promise<Partial<CloudflareEnv>> {
  const { getLocalD1Database } = await import('@/lib/local-d1')
  const { getLocalImageBucket } = await import('@/lib/local-image-bucket')

  return {
    DB: getLocalD1Database(),
    IMAGES: getLocalImageBucket(),
    ADMIN_PASSWORD: process.env.ADMIN_PASSWORD,
    ADMIN_TOKEN_SALT: process.env.ADMIN_TOKEN_SALT,
    AI_CONFIG_ENCRYPTION_SECRET: process.env.AI_CONFIG_ENCRYPTION_SECRET,
    AI_API_KEY: process.env.AI_API_KEY,
    AI_BASE_URL: process.env.AI_BASE_URL,
    AI_MODEL: process.env.AI_MODEL,
    WORKERS_AI_MODEL: process.env.WORKERS_AI_MODEL,
    ENABLE_BACKGROUND_JOBS: process.env.ENABLE_BACKGROUND_JOBS,
    ENABLE_WORKERS_AI: process.env.ENABLE_WORKERS_AI,
    ENABLE_VECTOR_SEARCH: process.env.ENABLE_VECTOR_SEARCH,
    ENABLE_CF_IMAGE_PIPELINE: process.env.ENABLE_CF_IMAGE_PIPELINE,
    NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL,
    CLOUDFLARE_ACCOUNT_ID: process.env.CLOUDFLARE_ACCOUNT_ID,
    CLOUDFLARE_API_TOKEN: process.env.CLOUDFLARE_API_TOKEN,
  }
}

function shouldUseLocalRuntime() {
  return (
    process.env.NODE_ENV === 'development' ||
    process.env.APP_RUNTIME === 'node' ||
    process.env.DEPLOY_TARGET === 'node' ||
    process.env.LOCAL_RUNTIME === 'true'
  )
}
