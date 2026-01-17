import { Marquee } from "@/components/magicui/marquee"

const testimonials = [
  {
    name: "karisayswen",
    username: "@karisaysw",
    body: "starred and downloaded. works perfectly for me! 💜 thank you for saving me the subscription fee for cleanshotx or other pay-to-use tools",
    img: "https://pbs.twimg.com/profile_images/2009375060021084160/Q_MzyhjI_400x400.jpg",
  },
  {
    name: "Luong NGUYEN",
    username: "@luongnv89",
    body: "wow, look so cool. installing it now! thanks for sharing.",
    img: "https://pbs.twimg.com/profile_images/1930379993705558016/ng7NjIwJ_400x400.jpg",
  },
  {
    name: "Sebastian Buzdugan",
    username: "@sebuzdugan",
    body: "open source wins again honestly",
    img: "https://pbs.twimg.com/profile_images/1803494807530004480/MpfF5Rpp_400x400.jpg",
  },
  {
    name: "Amrit",
    username: "@amritwt",
    body: "these tools generate good stuff \n\nlooks minor but does alot if you think about marketing",
    img: "https://pbs.twimg.com/profile_images/1941458464624214020/xSpt4E77_400x400.jpg",
  },
  {
    name: "Philipp Krenn",
    username: "@xeraa",
    body: "free and OSS alternative to CleanShot X:\n\n@bettershotsite\n\nbecause not everything needs 100 features and a cloud service.",
    img: "https://media.licdn.com/dms/image/v2/C4E03AQGjEcUTWv9uaw/profile-displayphoto-shrink_800_800/profile-displayphoto-shrink_800_800/0/1517750712975?e=1770249600&v=beta&t=bL5WF-BgL3A8LndSSOahU5YKFD7u1Z48yq9g_iqAq4k",
  },
  {
    name: "Harshith Ashvi",
    username: "@HarshithAshvi",
    body: "Don't build products, build an ecosystem of products.\n\n@stageeart\n - Browser based editor for creating visual design\n@bettershotsite\n - Mac app for screenshot and make it look good at same time\n\nAmazing work at great speed!",
    img: "https://pbs.twimg.com/profile_images/1953863730392862720/tGihM77m_400x400.jpg",
  },
  {
    name: "Fusion",
    username: "@fusion_ap",
    body: "love to see it! 🤌🤌🤌",
    img: "https://pbs.twimg.com/profile_images/2001652035729395713/I5anZIN2_400x400.jpg",
  },
  {
    name: "Rituraj",
    username: "@RituWithAI",
    body: "The subscription isn't the understatement of the year. We reached peak saturation when we started paying monthly rent for basic utilities like clipboards and screenshots. There is a massive market gap right now for 'Buy Once (or Free) / Keep Forever' software. You aren't just competing on features; you are competing on ideology. And you are winning.",
    img: "https://pbs.twimg.com/profile_images/1978096652964511744/CINo9gYa_400x400.jpg",
  },
  {
    name: "Gurbinder",
    username: "@legionsdev",
    body: "amazing tool",
    img: "https://pbs.twimg.com/profile_images/1924504051728670720/mqyGd02m_400x400.jpg",
  },
]

const firstColumn = testimonials.slice(0, 3)
const secondColumn = testimonials.slice(3, 6)
const thirdColumn = testimonials.slice(6, 9)

const TestimonialCard = ({
  img,
  name,
  username,
  body,
}: {
  img: string
  name: string
  username: string
  body: string
}) => {
  return (
    <div className="relative w-full max-w-xs overflow-hidden rounded-3xl border border-white/10 bg-gradient-to-b from-white/5 to-white/[0.02] p-10 shadow-[0px_2px_0px_0px_rgba(255,255,255,0.1)_inset]">
      <div className="absolute -top-5 -left-5 -z-10 h-40 w-40 rounded-full bg-gradient-to-b from-[#e78a53]/10 to-transparent blur-md"></div>

      <div className="text-white/90 leading-relaxed">{body}</div>

      <div className="mt-5 flex items-center gap-2">
        <img src={img || "/placeholder.svg"} alt={name} height="40" width="40" className="h-10 w-10 rounded-full" />
        <div className="flex flex-col">
          <div className="leading-5 font-medium tracking-tight text-white">{name}</div>
          <div className="leading-5 tracking-tight text-white/60">{username}</div>
        </div>
      </div>
    </div>
  )
}

export function TestimonialsSection() {
  return (
    <section id="testimonials" className="py-12 sm:py-24 md:py-32">
      <div className="mx-auto max-w-7xl">
        <div className="mx-auto max-w-[540px]">
          <div className="flex justify-center">
            <button
              type="button"
              className="group relative z-[60] mx-auto rounded-full border border-white/20 bg-white/5 px-6 py-1 text-xs backdrop-blur transition-all duration-300 hover:scale-105 hover:shadow-xl active:scale-100 md:text-sm"
            >
              <div className="absolute inset-x-0 -top-px mx-auto h-0.5 w-1/2 bg-gradient-to-r from-transparent via-[#e78a53] to-transparent shadow-2xl transition-all duration-500 group-hover:w-3/4"></div>
              <div className="absolute inset-x-0 -bottom-px mx-auto h-0.5 w-1/2 bg-gradient-to-r from-transparent via-[#e78a53] to-transparent shadow-2xl transition-all duration-500 group-hover:h-px"></div>
              <span className="relative text-white">Testimonials</span>
            </button>
          </div>
          <h2 className="from-foreground/60 via-foreground to-foreground/60 dark:from-muted-foreground/55 dark:via-foreground dark:to-muted-foreground/55 mt-5 bg-gradient-to-r bg-clip-text text-center text-4xl font-semibold tracking-tighter text-transparent md:text-[54px] md:leading-[60px] __className_bb4e88 relative z-10">
            What our users say
          </h2>

          <p className="mt-5 relative z-10 text-center text-lg text-zinc-500">
            Join developers and creators who use Better Shot to capture and enhance their screenshots every day.
          </p>
        </div>

        <div className="my-16 flex max-h-[738px] justify-center gap-6 overflow-hidden [mask-image:linear-gradient(to_bottom,transparent,black_25%,black_75%,transparent)]">
          <div>
            <Marquee pauseOnHover vertical className="[--duration:20s]">
              {firstColumn.map((testimonial) => (
                <TestimonialCard key={testimonial.username} {...testimonial} />
              ))}
            </Marquee>
          </div>

          <div className="hidden md:block">
            <Marquee reverse pauseOnHover vertical className="[--duration:25s]">
              {secondColumn.map((testimonial) => (
                <TestimonialCard key={testimonial.username} {...testimonial} />
              ))}
            </Marquee>
          </div>

          <div className="hidden lg:block">
            <Marquee pauseOnHover vertical className="[--duration:30s]">
              {thirdColumn.map((testimonial) => (
                <TestimonialCard key={testimonial.username} {...testimonial} />
              ))}
            </Marquee>
          </div>
        </div>

        <div className="-mt-8 flex justify-center">
          <a
            href="https://github.com/KartikLabhshetwar/better-shot"
            target="_blank"
            rel="noopener noreferrer"
            className="group relative inline-flex items-center gap-2 rounded-full border border-[#e78a53]/30 bg-black/50 px-6 py-3 text-sm font-medium text-white transition-all hover:border-[#e78a53]/60 hover:bg-[#e78a53]/10 active:scale-95"
          >
            <div className="absolute inset-x-0 -top-px mx-auto h-px w-3/4 bg-gradient-to-r from-transparent via-[#e78a53]/40 to-transparent"></div>
            <div className="absolute inset-x-0 -bottom-px mx-auto h-px w-3/4 bg-gradient-to-r from-transparent via-[#e78a53]/40 to-transparent"></div>
            <svg className="h-4 w-4 text-[#e78a53]" fill="currentColor" viewBox="0 0 24 24">
              <path d="M23.953 4.57a10 10 0 01-2.825.775 4.958 4.958 0 002.163-2.723c-.951.555-2.005.959-3.127 1.184a4.92 4.92 0 00-8.384 4.482C7.69 8.095 4.067 6.13 1.64 3.162a4.822 4.822 0 00-.666 2.475c0 1.71.87 3.213 2.188 4.096a4.904 4.904 0 01-2.228-.616v.06a4.923 4.923 0 003.946 4.827 4.996 4.996 0 01-2.212.085 4.936 4.936 0 004.604 3.417 9.867 9.867 0 01-6.102 2.105c-.39 0-.779-.023-1.17-.067a13.995 13.995 0 007.557 2.209c9.053 0 13.998-7.496 13.998-13.985 0-.21 0-.42-.015-.63A9.935 9.935 0 0024 4.59z"></path>
            </svg>
            Share on GitHub
          </a>
        </div>
      </div>
    </section>
  )
}
