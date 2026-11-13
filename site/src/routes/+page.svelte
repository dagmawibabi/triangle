<script lang="ts">
	import { onMount } from 'svelte';
	import type { PageProps } from './$types';
	import { setupReveals } from '#lib/motion.js';
	import BrandIcon from '#lib/components/BrandIcon.svelte';
	import Logo from '#lib/components/Logo.svelte';
	import Phone from '#lib/components/Phone.svelte';
	import Tri from '#lib/components/Tri.svelte';
	import TrianglePlate from '#lib/components/TrianglePlate.svelte';

	let { data }: PageProps = $props();

	const github = 'https://github.com/dagmawibabi/triangle';
	const releases = `${github}/releases`;
	// Always the newest release, as long as the file keeps this name.
	const companion = `${releases}/latest/download/Companion.rar`;

	const apps = [
		'Telegram',
		'Gmail',
		'Calendar',
		'Slack',
		'Notion',
		'Drive',
		'GitHub',
		'Linear',
		'Todoist'
	];

	const tabs = [
		{
			name: 'Ask anything',
			title: 'It reads everything you connected.',
			text: 'Ask one question across your chats, inbox, calendar and files, and get an answer with its sources.',
			prompt: 'What needs my attention before the launch?',
			tools: ['Searching your Telegram chats', 'Checking your calendar'],
			answer: 'Three things.',
			details: [
				'Alex is waiting for your go-ahead in the launch group.',
				'The design review is at 11:00. The files are in Drive.',
				'Your afternoon is clear.'
			]
		},
		{
			name: 'Make something',
			title: 'Images, audio and music from a sentence.',
			text: 'Everything you make is saved in Files, ready to send to a chat or open somewhere else.',
			prompt: 'Make a quiet ambient soundtrack for a focus session.',
			tools: ['Choosing an audio model', 'Generating a looping track'],
			answer: 'Your track is ready.',
			details: [
				'Soft rain and warm textures, with no sudden changes.',
				'It’s saved in Files.',
				'Want it sent to Telegram?'
			]
		},
		{
			name: 'Keep watch',
			title: 'It tells you when something happens.',
			text: 'Set a watch on a person or a group, build a routine that runs on a schedule, or wake up to a brief of what you missed.',
			prompt: 'Tell me when the final designs land in the launch group.',
			tools: ['Creating a watch', 'Following the launch group'],
			answer: 'Watching.',
			details: [
				'When the designs arrive, you’ll get a summary and the original message.',
				'You can pause or change this watch anytime.'
			]
		},
		{
			name: 'Track money',
			title: 'Your spending, from your bank texts.',
			text: 'It reads the texts your bank sends, keeps your accounts and budgets up to date, and answers questions about where the money went. The record stays on your phone.',
			prompt: 'How much did I spend on food this month?',
			tools: ['Reading your bank texts', 'Adding up your money'],
			answer: '4,280 birr on food so far.',
			details: [
				'That’s 18% more than last month, mostly from eating out.',
				'You have 1,720 birr left in your food budget.',
				'Your biggest day was Saturday, at 960 birr.'
			]
		},
		{
			name: 'Browse the web',
			title: 'It uses websites for you.',
			text: 'A real browser that reads pages, fills in forms, downloads files and takes screenshots. Watch it live, or take over whenever you like.',
			prompt: 'Find the visa form on the embassy site and fill in what you know.',
			tools: ['Opening the page in the browser', 'Filling in the form'],
			answer: 'It’s filled in, and waiting for you.',
			details: [
				'Your name and passport number are in.',
				'Two fields need you: travel dates and a photo.',
				'Open the browser to check it before you send it.'
			]
		},
		{
			name: 'Use your PC',
			title: 'Your computer, from your phone.',
			text: 'Run Triangle Companion on Windows. The assistant can find files, click, type and run commands, or you can watch the screen live and take over by touch.',
			prompt: 'Find last month’s invoice on my PC and send it to me.',
			tools: ['Searching your shared folders', 'Copying the file to your phone'],
			answer: 'It’s on your phone.',
			details: [
				'It was in Documents, under Invoices.',
				'The PDF is saved in Files.',
				'Only the folders you shared were searched.'
			]
		},
		{
			name: 'Run code',
			title: 'Python, charts and your cloud.',
			text: 'Run code in a sandbox, make charts, manage Cloudflare, and add more tools with MCP servers and skills.',
			prompt: 'Turn this CSV into a chart and save the result.',
			tools: ['Opening an E2B sandbox', 'Running Python'],
			answer: 'Your chart is ready.',
			details: [
				'The data is cleaned and grouped by month.',
				'The chart and the script are saved as files.',
				'Open them in the built-in editor to change anything.'
			]
		}
	];

	const finishSteps = [
		{
			title: 'Choose what it can do',
			text: 'Under <strong>Shared folders</strong>, click Add and pick the folders your phone may see. Then switch on <strong>See the screen</strong> to view the PC, and <strong>Control mouse &amp; keyboard</strong> to use it.'
		},
		{
			title: 'Add your PC to Triangle',
			text: 'On your phone, go to <strong>Settings → MCP &amp; Skills → MCP servers → Add by address</strong>. Name it pc and paste the address. Scanning the QR code in the companion with your camera or Google Lens is the easiest way to copy it.'
		},
		{
			title: 'Connect',
			text: 'Open the drawer in Triangle and tap <strong>PC screen</strong> to see your screen, or ask the assistant something like “What’s in my Documents folder?”'
		}
	];
	const guides = {
		wifi: {
			label: 'Home Wi-Fi',
			note: 'Nothing extra to install, but the phone must be on the same Wi-Fi as the PC, and the traffic isn’t encrypted. Use it only on your own network.',
			steps: [
				{
					title: 'Download and run it',
					text: 'Extract the whole folder and run <strong>triangle_companion</strong> from inside it. If Windows says it protected your PC, click <strong>More info</strong>, then <strong>Run anyway</strong>.'
				},
				{
					title: 'Pick Home Wi-Fi',
					text: 'Choose <strong>Home Wi-Fi</strong> at the top of the window. If Windows asks about network access, allow it on private networks. If you missed that, click <strong>Allow</strong> next to Windows Firewall.'
				},
				...finishSteps
			]
		},
		tailscale: {
			label: 'Tailscale',
			note: 'Encrypted and works from anywhere, and only your own devices can reach it. It takes a few more minutes to set up.',
			steps: [
				{
					title: 'Set up Tailscale',
					text: 'Install Tailscale on your PC and phone, and sign in to the same account on both. In the Tailscale admin console, go to <strong>DNS</strong> and turn on <strong>MagicDNS</strong> and <strong>HTTPS Certificates</strong>.'
				},
				{
					title: 'Download and run it',
					text: 'Extract the whole folder and run <strong>triangle_companion</strong> from inside it. If Windows says it protected your PC, click <strong>More info</strong>, then <strong>Run anyway</strong>.'
				},
				{
					title: 'Pick Tailscale',
					text: 'Choose <strong>Tailscale</strong> at the top of the window. The companion publishes itself. If it doesn’t, click <strong>Publish</strong>.'
				},
				...finishSteps
			]
		}
	};

	const shots = [
		{
			screen: 'assistant',
			title: 'Catch up in one message.',
			text: 'Your messages, email and calendar, answered in one place.',
			alt: 'Triangle assistant catching up on messages, email and calendar. Fictional sample conversation.'
		},
		{
			screen: 'watches',
			title: 'Hear about it when it happens.',
			text: 'A watch brings you the update and the message it came from.',
			alt: 'Triangle watch update summarizing a team’s launch progress. Fictional sample conversation.'
		},
		{
			screen: 'brief',
			title: 'Start the day with a brief.',
			text: 'Everything that happened overnight, with what needs you first.',
			alt: 'Triangle morning brief listing the day’s priorities. Fictional sample content.'
		}
	];

	const principles = [
		{
			title: 'You approve it first',
			text: 'Sends and changes wait for your OK, and you can edit them before they go.'
		},
		{
			title: 'Your keys stay on your phone',
			text: 'Bring your own AI provider and pick your own models.'
		},
		{
			title: 'You set the limits',
			text: 'Turn tools on one at a time, or switch everything to read-only.'
		}
	];

	const questions = [
		{
			question: 'What is Triangle?',
			answer:
				'An AI workspace for Android that connects your conversations, apps and everyday tools. It includes a full Telegram client, an assistant that works across connected services, creative tools, briefs and watches.'
		},
		{
			question: 'Is it free?',
			answer:
				'You can download Triangle from GitHub. You bring your own AI provider key, and that provider bills you for what you use. Optional services such as web search, connected apps, voice generation and cloud sandboxes may need their own keys or paid accounts.'
		},
		{
			question: 'Do I need a Telegram account?',
			answer:
				'No. You can start with AI chat, connected apps, cloud tools and your phone, then connect Telegram later in Settings → Apps & web.'
		},
		{
			question: 'Which AI models can I use?',
			answer:
				'You choose your own chat, image and audio models in Settings → AI & models. Providers include Vercel AI Gateway, OpenRouter, OpenCode Zen, Google AI Studio and LM Studio on your own computer, with ElevenLabs and Addis AI for voices and TypeSafe Jev for decisions. The model list shows only the providers you added a key for. You can also ask the assistant to add or change a key, and it asks you before saving it.'
		},
		{
			question: 'Can I change how the assistant behaves?',
			answer:
				'Yes. Give it standing instructions in Settings → Assistant, and choose how long its answers are and which language it answers in. You can also see the exact system prompt it follows, then edit it, clear it, turn it off or reset it to the default.'
		},
		{
			question: 'What happens to my data?',
			answer:
				'Your API keys are stored on your device. When you use an AI model or a connected service, the information needed for that request goes to that provider. You choose which tools the assistant can use, and sending or changing things asks for your approval by default.'
		},
		{
			question: 'Can Triangle use my computer?',
			answer:
				'Yes, on Windows, with Triangle Companion running on your PC and your phone connected over Tailscale or home Wi-Fi. Each ability has its own switch on the PC: shared folders, seeing the screen, mouse and keyboard, the clipboard, commands, and apps and system. Changes can be set to ask for your OK on the PC first.'
		},
		{
			question: 'Does it read my bank texts?',
			answer:
				'Only if you allow it. The money tools read the texts your bank sends to keep track of your accounts, spending and budgets. That record is kept on your phone, and you can add, fix or delete anything yourself.'
		},
		{
			question: 'Can I hide people, channels or words in Telegram?',
			answer:
				'Yes. Settings → Block & mute hides messages from people you blocked, posts forwarded from channels and groups you block, and anything with a word you muted, in chats, groups, channels and comments. Each can leave a “tap to view” notice or disappear completely.'
		},
		{
			question: 'How do I install it?',
			answer:
				'Open the GitHub releases page, download the APK for your Android device and install it. Android may ask you to allow installs from your browser or file manager. Then open Triangle, add an AI provider key and connect the apps you want.'
		}
	];

	let selectedTab = $state(0);
	let activeShot = $state(0);
	let guideMode = $state<'wifi' | 'tailscale'>('wifi');
	let approval = $state<'pending' | 'approved' | 'dismissed'>('pending');
	let dialogShot = $state(shots[0]);
	let screenshotDialog: HTMLDialogElement;
	let demoElement: HTMLElement;

	// The demo starts complete, so it reads fine before scripts load or with
	// reduced motion; play() rewinds it and writes it out.
	let typed = $state(Infinity);
	let toolsDone = $state(99);
	let linesShown = $state(99);

	const example = $derived(tabs[selectedTab]);

	let timers: number[] = [];
	let reducedMotion = false;

	function play() {
		timers.forEach(clearTimeout);
		timers = [];
		if (reducedMotion) return;
		typed = 0;
		toolsDone = 0;
		linesShown = 0;
		const prompt = example.prompt;
		const tools = example.tools.length;
		const lines = example.details.length + 1;
		const typing = 16;
		for (let i = 1; i <= prompt.length; i++) {
			timers.push(window.setTimeout(() => (typed = i), i * typing));
		}
		let at = prompt.length * typing + 260;
		for (let i = 1; i <= tools; i++) {
			at += 420;
			timers.push(window.setTimeout(() => (toolsDone = i), at));
		}
		at += 200;
		for (let i = 1; i <= lines; i++) {
			at += 300;
			timers.push(window.setTimeout(() => (linesShown = i), at));
		}
		timers.push(
			window.setTimeout(() => {
				typed = Infinity;
			}, at)
		);
	}

	function selectTab(index: number) {
		if (index === selectedTab) return;
		selectedTab = index;
		play();
	}

	function tabKeys(event: KeyboardEvent) {
		const forward = ['ArrowDown', 'ArrowRight'].includes(event.key);
		const back = ['ArrowUp', 'ArrowLeft'].includes(event.key);
		if (!forward && !back && event.key !== 'Home' && event.key !== 'End') return;
		event.preventDefault();
		const next =
			event.key === 'Home'
				? 0
				: event.key === 'End'
					? tabs.length - 1
					: (selectedTab + (forward ? 1 : -1) + tabs.length) % tabs.length;
		selectTab(next);
		document.getElementById(`tab-${next}`)?.focus();
	}

	function showShot(shot: (typeof shots)[number]) {
		dialogShot = shot;
		screenshotDialog.showModal();
	}

	onMount(() => {
		reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

		const stopReveals = setupReveals();

		const demoSeen = new IntersectionObserver(
			([entry]) => {
				if (entry.isIntersecting) {
					play();
					demoSeen.disconnect();
				}
			},
			{ threshold: 0.35 }
		);
		demoSeen.observe(demoElement);

		const shotSeen = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (entry.isIntersecting) activeShot = Number((entry.target as HTMLElement).dataset.shot);
				}
			},
			{ rootMargin: '-48% 0px -48% 0px' }
		);
		document.querySelectorAll('[data-shot]').forEach((element) => shotSeen.observe(element));

		return () => {
			timers.forEach(clearTimeout);
			stopReveals();
			demoSeen.disconnect();
			shotSeen.disconnect();
		};
	});
</script>

<svelte:head>
	<title>Triangle: your world, one conversation</title>
	<meta
		name="description"
		content="Triangle brings AI, Telegram, your apps, your phone and your PC into one conversation. For Android, with your own AI keys."
	/>
	<meta property="og:title" content="Triangle: your world, one conversation" />
	<meta
		property="og:description"
		content="Your chats, your apps, your PC and your AI, in one conversation on your phone."
	/>
	<meta property="og:type" content="website" />
	<meta property="og:image" content="/social-preview.jpg" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta property="og:image:type" content="image/jpeg" />
	<meta
		property="og:image:alt"
		content="Triangle. Your world, one conversation. App previews of the assistant and morning brief."
	/>
	<meta name="twitter:card" content="summary_large_image" />
</svelte:head>

<main id="main">
	<section class="hero" aria-labelledby="hero-heading">
		<TrianglePlate />
		<div class="hero-copy">
			<h1 id="hero-heading">
				<span class="line"><span>Your world.</span></span>
				<span class="line"><span>One conversation.</span></span>
			</h1>
			<p class="hero-text">
				Your chats, apps, phone and PC, with an AI that can work across all of them.
			</p>
			<div class="hero-actions">
				<a class="button" data-magnetic href="#download"><span>Get it for Android</span><Tri /></a>
				<a class="link" href="#features"><span>See what it does</span></a>
			</div>
		</div>
	</section>

	<section class="ticker" aria-label="Apps Triangle connects to">
		<div class="ticker-track">
			{#each [0, 1] as copy}
				<ul aria-hidden={copy === 1}>
					{#each apps as app}
						<li><BrandIcon name={app} size={26} /><span>{app}</span></li>
					{/each}
					<li class="ticker-more"><span>and 500+ more</span></li>
				</ul>
			{/each}
		</div>
	</section>

	<section class="features band" id="features" aria-labelledby="features-heading">
		<div class="heading" data-reveal="type">
			<h2 id="features-heading">One conversation that can do the work.</h2>
		</div>
		<div class="features-layout">
			<div
				class="tab-list"
				role="tablist"
				aria-label="What Triangle does"
				aria-orientation="vertical"
				data-reveal
			>
				{#each tabs as tab, index}
					<button
						type="button"
						role="tab"
						id={`tab-${index}`}
						aria-selected={selectedTab === index}
						aria-controls="feature-panel"
						tabindex={selectedTab === index ? 0 : -1}
						class:active={selectedTab === index}
						onclick={() => selectTab(index)}
						onkeydown={tabKeys}
					>
						<Tri size={13} class="tab-mark" /><span>{tab.name}</span>
					</button>
				{/each}
			</div>
			<div
				class="feature-panel"
				id="feature-panel"
				role="tabpanel"
				aria-labelledby={`tab-${selectedTab}`}
				tabindex="0"
				bind:this={demoElement}
			>
				{#key selectedTab}
					<div class="panel-copy">
						<h3>{example.title}</h3>
						<p>{example.text}</p>
					</div>
				{/key}
				<div class="demo">
					<div class="demo-bar">
						<Logo size={15} /><span>Example conversation</span>
					</div>
					<div class="demo-body">
						<p class="sr-only">{example.prompt}</p>
						<div class="demo-user" aria-hidden="true">
							{typed === Infinity
								? example.prompt
								: example.prompt.slice(
										0,
										typed
									)}{#if typed !== Infinity && typed < example.prompt.length}<i class="caret"
								></i>{/if}
						</div>
						<ul class="demo-tools">
							{#each example.tools as tool, index}
								<li class:done={toolsDone > index} class:waiting={toolsDone < index}>
									<i></i><span>{tool}</span>
								</li>
							{/each}
						</ul>
						<div class="demo-answer">
							<h4 class:shown={linesShown > 0}>{example.answer}</h4>
							{#each example.details as detail, index}
								<p class:shown={linesShown > index + 1}>{detail}</p>
							{/each}
						</div>
					</div>
				</div>
			</div>
		</div>
	</section>

	<section class="shots" aria-labelledby="shots-heading">
		<h2 id="shots-heading" class="sr-only">The app</h2>
		<div class="shots-steps">
			{#each shots as shot, index}
				<article data-shot={index} class:active={activeShot === index}>
					<h3>{shot.title}</h3>
					<p>{shot.text}</p>
					<button
						class="shots-inline"
						type="button"
						onclick={() => showShot(shot)}
						aria-label={`Enlarge: ${shot.title}`}
					>
						<Phone screen={shot.screen} alt={shot.alt} />
					</button>
				</article>
			{/each}
		</div>
		<div class="shots-stage">
			<button
				class="shots-phone"
				type="button"
				onclick={() => showShot(shots[activeShot])}
				aria-label={`Enlarge: ${shots[activeShot].title}`}
			>
				{#each shots as shot, index}
					<span
						class="shot-layer"
						class:active={activeShot === index}
						class:past={activeShot > index}
					>
						<Phone screen={shot.screen} alt={activeShot === index ? shot.alt : ''} />
					</span>
				{/each}
				<span class="phone-sizer"><Phone screen={shots[0].screen} alt="" /></span>
			</button>
			<ol class="shots-index" aria-hidden="true">
				{#each shots as _, index}<li class:active={activeShot === index}></li>{/each}
			</ol>
		</div>
	</section>

	<section class="tools band" id="apps" aria-labelledby="tools-heading">
		<div class="heading" data-reveal="type">
			<h2 id="tools-heading">A small shape with a lot inside.</h2>
		</div>
		<div class="grid">
			<article class="cell span-4 cell-voice wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<svg viewBox="0 0 200 180" class="voice-tri">
						<defs>
							<clipPath id="voice-clip"><path d="M100 8 192 170H8Z" /></clipPath>
							<filter
								id="voice-blur"
								filterUnits="userSpaceOnUse"
								x="-60"
								y="-20"
								width="320"
								height="240"><feGaussianBlur stdDeviation="9" /></filter
							>
							<linearGradient id="voice-sky" x1="0" y1="0" x2="0" y2="1">
								<stop offset="0" stop-color="#000" />
								<stop offset=".42" stop-color="#17171a" />
								<stop offset=".62" stop-color="#b4b4b8" />
								<stop offset="1" stop-color="#f2f2f3" />
							</linearGradient>
						</defs>
						<g clip-path="url(#voice-clip)">
							<rect width="200" height="180" fill="url(#voice-sky)" />
							<g filter="url(#voice-blur)" fill="#fff">
								<circle class="cloud c1" cx="50" cy="118" r="26" />
								<circle class="cloud c2" cx="100" cy="104" r="30" />
								<circle class="cloud c3" cx="150" cy="120" r="24" />
							</g>
						</g>
						<path d="M100 8 192 170H8Z" fill="none" stroke="#555" />
					</svg>
				</div>
				<div class="copy">
					<h3>Voice mode</h3>
					<p>
						Talk hands-free. It answers out loud while it writes, and the triangle moves with both
						voices. Drag it down to read along.
					</p>
				</div>
			</article>
			<article class="cell span-2 cell-search wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<div class="search-line"><span>That idea from last week</span><i class="caret"></i></div>
					<ul class="search-hits">
						<li>Your conversations</li>
						<li>Your inbox</li>
						<li>The web</li>
					</ul>
				</div>
				<div class="copy">
					<h3>One search</h3>
					<p>Conversations, Telegram, email, files and the web.</p>
				</div>
			</article>
			<article class="cell span-4 cell-browser wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<div class="browser-win">
						<div class="browser-bar">
							<Tri size={9} turn={270} /><span>wikipedia.org/wiki/Moon</span>
						</div>
						<div class="browser-page">
							<i style="--w: 62%"></i>
							<i style="--w: 92%"></i>
							<i style="--w: 84%"></i>
							<i style="--w: 48%"></i>
							<b></b>
						</div>
					</div>
				</div>
				<div class="copy">
					<h3>A real browser</h3>
					<p>
						It reads pages, fills in forms, clicks through sites, downloads files and takes
						screenshots. Watch it live, or take over whenever you like.
					</p>
				</div>
			</article>
			<article class="cell span-2 cell-creative wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<div class="bars">
						{#each Array.from({ length: 22 }) as _, i}<i
								style={`--h: ${18 + (Math.sin(i * 0.9) + 1) * 28 + (i % 3) * 7}px; --d: ${i * -0.09}s`}
							></i>{/each}
					</div>
				</div>
				<div class="copy">
					<h3>Make things</h3>
					<p>
						Images, speech, music and video from a description. Resize, crop or cut out a picture.
					</p>
				</div>
			</article>
			<article class="cell span-3 cell-pc wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<svg viewBox="0 0 240 150" class="pc-screen">
						<rect
							x=".5"
							y=".5"
							width="239"
							height="149"
							fill="none"
							stroke="currentColor"
							opacity=".4"
						/>
						<path d="M0 18H240" stroke="currentColor" opacity=".4" />
						<path class="pc-trail" d="M120 40 180 124H60Z" pathLength="1" />
						<circle class="pc-click" cx="120" cy="40" r="4" />
						<circle class="pc-click two" cx="180" cy="124" r="4" />
						<circle class="pc-click three" cx="60" cy="124" r="4" />
						<path class="pc-cursor" d="M0 0 0 15 4 11 7 18 10 17 7 10 13 10Z" />
					</svg>
				</div>
				<div class="copy">
					<h3>Your PC</h3>
					<p>
						Triangle Companion for Windows lets it move the mouse, type, open apps and reach the
						folders you share. You can watch and take over live.
					</p>
					<a class="link cell-link" href="#companion"><span>Set up Triangle Companion</span></a>
				</div>
			</article>
			<article class="cell span-3 cell-telegram wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<ul class="chat-lines">
						<li><i></i><span style="--w: 62%"></span></li>
						<li class="me"><span style="--w: 44%"></span><i></i></li>
						<li><i></i><span style="--w: 74%"></span></li>
						<li class="me"><span style="--w: 30%"></span><i></i></li>
					</ul>
				</div>
				<div class="copy">
					<h3>A whole Telegram client</h3>
					<p>
						Chats, channels, folders, files, stickers and voice notes, with several accounts at once
						and search that remembers what you looked for.
					</p>
				</div>
			</article>
			<article class="cell span-2 cell-brief wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<ul class="brief-lines">
						<li><i></i><span style="--w: 88%"></span></li>
						<li><i></i><span style="--w: 66%"></span></li>
						<li><i></i><span style="--w: 76%"></span></li>
						<li><i></i><span style="--w: 42%"></span></li>
					</ul>
				</div>
				<div class="copy">
					<h3>Morning and night briefs</h3>
					<p>What happened across your chats, with what needs you first.</p>
				</div>
			</article>
			<article class="cell span-2 cell-reminders wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<svg class="clock" viewBox="0 0 120 120">
						<circle cx="60" cy="60" r="54" />
						<circle class="clock-tick" cx="60" cy="60" r="47" pathLength="201" />
						<path class="clock-hand" d="M60 18 66 62H54Z" />
					</svg>
				</div>
				<div class="copy">
					<h3>Routines</h3>
					<p>“Every weekday at 9, catch me up on my channels.” Jobs it runs on a schedule.</p>
				</div>
			</article>
			<article class="cell span-2 cell-memory wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<svg class="memory-map" viewBox="0 0 120 104">
						<path d="M60 8 112 96H8Z" pathLength="1" />
						<circle cx="60" cy="8" r="5" />
						<circle cx="112" cy="96" r="5" />
						<circle cx="8" cy="96" r="5" />
					</svg>
				</div>
				<div class="copy">
					<h3>Memory</h3>
					<p>It remembers your preferences and the people you mention, across chats.</p>
				</div>
			</article>
			<article class="cell span-2 cell-canvas wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<div class="sheets"><i></i><i></i><i></i></div>
				</div>
				<div class="copy">
					<h3>Content Canvas</h3>
					<p>A home for links, emails, files and saved messages.</p>
				</div>
			</article>
			<article class="cell span-2 cell-phone wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<ul class="switches">
						<li><span>Alarm at 7:00</span><i></i></li>
						<li><span>Flashlight</span><i></i></li>
						<li><span>Call Sara</span><i></i></li>
					</ul>
				</div>
				<div class="copy">
					<h3>Your phone</h3>
					<p>Find a text, read notifications, check screen time and data use, or call someone.</p>
				</div>
			</article>
			<article class="cell span-2 cell-code wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<code class="term">
						<span>chart = plot(sales)</span>
						<span>chart.save("q3.png")</span>
						<span class="term-done">Saved q3.png</span>
					</code>
				</div>
				<div class="copy">
					<h3>Cloud and code</h3>
					<p>Cloudflare, E2B sandboxes, MCP servers and skills.</p>
				</div>
			</article>
			<article class="cell span-3 cell-discover wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<div class="posters"><i></i><i></i><i></i></div>
				</div>
				<div class="copy">
					<h3>Things to watch, read and hear</h3>
					<p>
						YouTube, X, Reddit, Hacker News, research papers, books, audiobooks, podcasts, radio,
						films and music, with results you can open right there.
					</p>
				</div>
			</article>
			<article class="cell span-3 cell-widgets wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<div class="tiles"><i></i><i></i><i></i><i></i><i></i></div>
				</div>
				<div class="copy">
					<h3>Home-screen widgets</h3>
					<p>Ask for a widget in your own words, and it builds one for your home screen.</p>
				</div>
			</article>
			<article class="cell span-2 cell-money wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<ul class="ledger">
						<li><span>Salary</span><b>+24,000</b></li>
						<li><span>Groceries</span><b>−840</b></li>
						<li><span>Taxi</span><b>−210</b></li>
						<li class="ledger-budget"><span>Food budget</span><i style="--w: 62%"></i></li>
					</ul>
				</div>
				<div class="copy">
					<h3>Money</h3>
					<p>
						Accounts, budgets and spending from your bank texts, plus prices, markets and
						currencies.
					</p>
				</div>
			</article>
			<article class="cell span-2 cell-mute wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<ul class="muted-msgs">
						<li><i></i><span style="--w: 70%"></span></li>
						<li class="muted">
							<em>Message from someone you blocked</em><small>Tap to view</small>
						</li>
						<li><i></i><span style="--w: 52%"></span></li>
					</ul>
				</div>
				<div class="copy">
					<h3>Block and mute</h3>
					<p>
						Hide people, channels and words in chats, groups and comments, behind a notice or
						without a trace.
					</p>
				</div>
			</article>
			<article class="cell span-2 cell-everyday wipe" data-reveal>
				<div class="art" aria-hidden="true">
					<ul class="topics">
						<li>Scores</li>
						<li>Recipes</li>
						<li>Weather</li>
						<li>Verse of the day</li>
						<li>Ethiopian date</li>
						<li>QR codes</li>
					</ul>
				</div>
				<div class="copy">
					<h3>Everyday answers</h3>
					<p>Words and translation, sports, recipes, the Bible, holidays, flights and QR codes.</p>
				</div>
			</article>
		</div>
		<div class="all-tools" data-reveal>
			<p>And the rest: {data.toolCount} tools in all.</p>
			<a class="button" data-magnetic href="/tools"><span>See every tool</span><Tri /></a>
		</div>
	</section>

	<section class="companion-section band" id="companion" aria-labelledby="companion-heading">
		<div class="companion-top">
			<div data-reveal="type"><h2 id="companion-heading">Triangle Companion, for your PC.</h2></div>
			<div data-reveal>
				<p>
					A small Windows app that connects your phone to your PC. See and use your screen by touch,
					or let the assistant find files, click, type and run commands. Nothing is on until you
					switch it on.
				</p>
				<div class="companion-actions">
					<a class="button" data-magnetic href={companion}
						><span>Download Companion</span><Tri turn={180} /></a
					>
					<a class="link" href="/tools#pc"><span>See its tools</span></a>
				</div>
			</div>
		</div>
		<div class="guide">
			<div class="guide-side" data-reveal>
				<h3>Set it up and connect.</h3>
				<div
					class="modes"
					role="group"
					aria-label="How to connect"
					style={`--mode: ${guideMode === 'wifi' ? 0 : 1}`}
				>
					{#each Object.entries(guides) as [mode, guide]}
						<button
							type="button"
							class:active={guideMode === mode}
							aria-pressed={guideMode === mode}
							onclick={() => (guideMode = mode as 'wifi' | 'tailscale')}
						>
							{guide.label}
						</button>
					{/each}
				</div>
				{#key guideMode}<p class="mode-note">{guides[guideMode].note}</p>{/key}
			</div>
			{#key guideMode}
				<ol class="guide-steps">
					{#each guides[guideMode].steps as step, index}
						<li style={`--i: ${index}`}>
							<h4>{step.title}</h4>
							<p>{@html step.text}</p>
						</li>
					{/each}
				</ol>
			{/key}
		</div>
		<div class="companion-facts" data-reveal>
			<div>
				<h4>Using the screen by touch</h4>
				<ul>
					<li><b>Tap</b> to click, and tap twice to double-click</li>
					<li><b>Long-press</b> to right-click, then move to drag</li>
					<li><b>One finger</b> to scroll, and <b>two</b> to zoom and pan</li>
					<li><b>Keyboard button</b> to type, with Esc, Tab, arrows and shortcuts</li>
				</ul>
			</div>
			<div>
				<h4>What you switch on</h4>
				<ul>
					<li><b>Shared folders</b>, and whether each can be changed</li>
					<li><b>See the screen</b></li>
					<li><b>Control mouse &amp; keyboard</b></li>
					<li><b>Clipboard</b>, <b>Run commands</b>, and <b>Apps &amp; system</b></li>
				</ul>
			</div>
			<div>
				<h4>If it won’t connect</h4>
				<ul>
					<li>
						<b>No PC found:</b> check the companion is running, the phone is on the same network, and
						your Wi-Fi is set to Private in Windows
					</li>
					<li><b>The PC refused:</b> See the screen is off, or the companion is paused</li>
					<li><b>Touches do nothing:</b> switch on Control mouse &amp; keyboard</li>
				</ul>
			</div>
		</div>
	</section>

	<section class="control band" id="control" aria-labelledby="control-heading">
		<div class="control-copy">
			<div data-reveal="type"><h2 id="control-heading">Nothing goes out until you say so.</h2></div>
			<ul class="principles" data-reveal>
				{#each principles as item}
					<li>
						<h3>{item.title}</h3>
						<p>{item.text}</p>
					</li>
				{/each}
			</ul>
		</div>
		<div
			class="approval"
			class:approved={approval === 'approved'}
			class:dismissed={approval === 'dismissed'}
			data-reveal
		>
			<p class="approval-top">Telegram, to Launch team</p>
			<h3>Send this reply?</h3>
			<blockquote>The designs look great. Let’s ship on Friday. Thanks, everyone!</blockquote>
			<div class="approval-actions" aria-live="polite">
				{#if approval === 'pending'}
					<button
						type="button"
						class="button"
						data-magnetic
						onclick={() => (approval = 'approved')}
					>
						<span>Approve</span>
					</button>
					<button
						type="button"
						class="button ghost"
						data-magnetic
						onclick={() => (approval = 'dismissed')}
					>
						<span>Decline</span>
					</button>
				{:else}
					<div class="approval-result">
						<svg viewBox="0 0 40 40" width="26" height="26" fill="none" aria-hidden="true">
							<path d="M20 5 37 34H3Z" pathLength="1" />
						</svg>
						<span
							>{approval === 'approved'
								? 'Approved. In the app, this would send now.'
								: 'Declined. Nothing was sent.'}</span
						>
					</div>
					<button class="link" type="button" onclick={() => (approval = 'pending')}
						><span>Try again</span></button
					>
				{/if}
			</div>
			<p class="approval-note">This is a demo, so nothing is really sent.</p>
		</div>
	</section>

	<section class="setup band" aria-labelledby="setup-heading">
		<div class="heading" data-reveal="type"><h2 id="setup-heading">Set up in three steps.</h2></div>
		<ol class="steps">
			<li data-reveal style="--delay: 0ms">
				<span class="step-number" aria-hidden="true">1</span>
				<h3>Install it</h3>
				<p>Download the Android APK from the latest GitHub release.</p>
			</li>
			<li data-reveal style="--delay: 120ms">
				<span class="step-number" aria-hidden="true">2</span>
				<h3>Add your keys</h3>
				<p>Add an AI provider key and connect your apps. Telegram can wait until you’re ready.</p>
			</li>
			<li data-reveal style="--delay: 240ms">
				<span class="step-number" aria-hidden="true">3</span>
				<h3>Ask something</h3>
				<p>Try “Catch me up on my day.”</p>
			</li>
		</ol>
	</section>

	<section class="faq band" aria-labelledby="faq-heading">
		<div class="heading" data-reveal="type"><h2 id="faq-heading">Questions.</h2></div>
		<div class="faq-list" data-reveal>
			{#each questions as item}
				<details name="triangle-faq">
					<summary><span>{item.question}</span><Tri size={12} class="faq-mark" /></summary>
					<p>
						{item.answer}
						{#if item.question === 'Can Triangle use my computer?'}
							<a class="link" href="#companion"><span>Set up Triangle Companion</span></a>
						{/if}
					</p>
				</details>
			{/each}
		</div>
	</section>

	<section class="download" id="download" aria-labelledby="download-heading">
		<svg class="download-tri" viewBox="0 0 600 520" fill="none" aria-hidden="true">
			<path d="M300 20 580 505H20Z" stroke="currentColor" stroke-width="56" />
		</svg>
		<div class="download-copy">
			<div data-reveal="type"><h2 id="download-heading">Bring it all together.</h2></div>
			<p>Triangle is for Android. Triangle Companion lets it use your Windows PC.</p>
			<div class="download-actions">
				<a class="button dark" data-magnetic href={releases} target="_blank" rel="noreferrer">
					<span>Download Triangle</span><Tri turn={180} />
				</a>
				<a class="button dark" data-magnetic href={companion}>
					<span>Download Companion</span><Tri turn={180} />
				</a>
			</div>
			<a class="link download-source" href={github} target="_blank" rel="noreferrer"
				><span>Read the source</span></a
			>
		</div>
	</section>
</main>

<dialog bind:this={screenshotDialog} class="shot-dialog" aria-labelledby="dialog-title">
	<div class="dialog-bar">
		<h2 id="dialog-title">{dialogShot.title}</h2>
		<button type="button" class="link" onclick={() => screenshotDialog.close()}
			><span>Close</span></button
		>
	</div>
	<img
		src={`/screenshots/${dialogShot.screen}.png`}
		alt={dialogShot.alt}
		width="780"
		height="1640"
	/>
	<p>Screenshots use fictional conversations.</p>
</dialog>
