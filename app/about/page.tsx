import { SiteFooter } from '@/components/SiteFooter'
import { SiteHeader } from '@/components/SiteHeader'
import { getAppCloudflareEnv } from '@/lib/cloudflare'
import { getSiteHeaderData, type SiteCategoryLink, type SiteNavLink } from '@/lib/site'
import type { Theme } from '@/lib/appearance'

export const metadata = {
  title: '关于',
  description: '关于玄木博客：沉淀原创思考、读书笔记、文章摘录与项目复盘。',
}

export default async function AboutPage() {
  let navLinks: SiteNavLink[] = []
  let categories: SiteCategoryLink[] = []
  let defaultTheme: Theme = 'default'

  try {
    const env = await getAppCloudflareEnv()
    if (env?.DB) {
      const headerData = await getSiteHeaderData(env.DB)
      navLinks = headerData.navLinks
      categories = headerData.categories
      defaultTheme = headerData.defaultTheme
    }
  } catch {}

  return (
    <div className="min-h-full flex flex-col bg-[var(--background)]">
      <SiteHeader
        initialTheme={defaultTheme}
        navLinks={navLinks}
        categories={categories}
        stickyOnMobile={false}
      />
      <main className="mx-auto w-full max-w-3xl flex-1 px-4 py-12 sm:px-6 sm:py-16">
        <article className="prose prose-neutral max-w-none">
          <p className="text-sm font-medium text-[var(--editor-accent)]">ABOUT</p>
          <h1 className="mt-3 text-3xl font-bold tracking-tight text-[var(--editor-ink)]">
            玄木博客
          </h1>
          <p className="mt-5 text-base leading-8 text-[var(--editor-muted)]">
            这里不是临时收藏夹，而是一个长期知识资产库。它用来沉淀原创思考、读书笔记、文章摘录、工具方法和项目复盘。
          </p>
          <p className="mt-4 text-base leading-8 text-[var(--editor-muted)]">
            每篇转载或摘录都应该带着自己的判断：这篇内容说了什么、哪里值得保留、它能怎样被用到真实生活和工作里。
          </p>
          <h2 className="mt-10 text-xl font-semibold text-[var(--editor-ink)]">内容原则</h2>
          <ul className="mt-4 space-y-3 text-sm leading-7 text-[var(--editor-muted)]">
            <li>原创内容优先，摘录内容必须附带个人理解。</li>
            <li>分类保持克制，方便长期检索和复用。</li>
            <li>少做情绪化堆积，多做结构化沉淀。</li>
          </ul>
        </article>
      </main>
      <SiteFooter />
    </div>
  )
}
