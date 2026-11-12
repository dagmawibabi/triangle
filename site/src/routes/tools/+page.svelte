<script lang="ts">
	import { onMount } from 'svelte';
	import type { PageProps } from './$types';
	import { setupReveals } from '#lib/motion.js';
	import Tri from '#lib/components/Tri.svelte';

	let { data }: PageProps = $props();

	const kinds = [
		{ id: 'all', label: 'All' },
		{ id: 'read', label: 'Reads' },
		{ id: 'modify', label: 'Changes' },
		{ id: 'destructive', label: 'Deletes' }
	];
	const kindName: Record<string, string> = {
		read: 'Reads',
		modify: 'Changes',
		destructive: 'Deletes'
	};

	let query = $state('');
	let kind = $state('all');
	let activeGroup = $state('');
	let searchBox: HTMLInputElement;

	const words = $derived(query.toLowerCase().split(/\s+/).filter(Boolean));
	const shown = $derived(
		data.groups
			.map((group) => ({
				...group,
				categories: group.categories
					.map((category) => ({
						...category,
						tools: category.tools.filter((tool) => {
							if (kind !== 'all' && tool.access !== kind) return false;
							const text =
								`${tool.label} ${tool.name} ${tool.summary} ${category.title} ${group.title}`.toLowerCase();
							return words.every((word) => text.includes(word));
						})
					}))
					.filter((category) => category.tools.length > 0)
			}))
			.filter((group) => group.categories.length > 0)
	);
	const countOf = (group: { categories: { tools: unknown[] }[] }) =>
		group.categories.reduce((sum, category) => sum + category.tools.length, 0);
	const total = $derived(shown.reduce((sum, group) => sum + countOf(group), 0));
	const filtering = $derived(words.length > 0 || kind !== 'all');

	function clear() {
		query = '';
		kind = 'all';
		searchBox.focus();
	}

	function shortcut(event: KeyboardEvent) {
		const typing = (event.target as HTMLElement)?.matches?.('input, textarea');
		if (event.key === '/' && !typing) {
			event.preventDefault();
			searchBox.focus();
		} else if (event.key === 'Escape' && event.target === searchBox) {
			query = '';
		}
	}

	// Which group is in view, for the side list.
	let spy: IntersectionObserver | undefined;
	$effect(() => {
		void shown;
		spy?.disconnect();
		spy = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (entry.isIntersecting) activeGroup = entry.target.id;
				}
			},
			{ rootMargin: '-25% 0px -70% 0px' }
		);
		document.querySelectorAll('.tool-group').forEach((element) => spy?.observe(element));
	});

	onMount(() => {
		const stop = setupReveals();
		return () => {
			stop();
			spy?.disconnect();
		};
	});
</script>

<svelte:window onkeydown={shortcut} />
<svelte:head>
	<title>All tools: Triangle</title>
	<meta
		name="description"
		content={`Every tool in Triangle, by what it works with: ${data.toolCount} tools for Telegram, your apps, your phone, your money, your PC, the web, everyday questions and the cloud.`}
	/>
	<meta property="og:title" content="All Triangle tools" />
	<meta property="og:type" content="website" />
</svelte:head>

<main id="main" class="catalogue">
	<section class="catalogue-top" aria-labelledby="catalogue-heading">
		<h1 id="catalogue-heading" class="catalogue-title">
			<span class="line"><span>{data.toolCount} tools.</span></span>
			<span class="line"><span>One conversation.</span></span>
		</h1>
		<p class="catalogue-intro">
			You don’t need to learn any of these. Ask in your own words and the assistant picks the right
			tool. You choose which ones it may use, and changes ask for your OK by default.
		</p>
	</section>

	<div class="finder">
		<label class="search">
			<span class="sr-only">Search tools</span>
			<Tri size={12} turn={90} />
			<input
				bind:this={searchBox}
				bind:value={query}
				type="search"
				placeholder="Search tools, like “alarm” or “email”"
				autocomplete="off"
				spellcheck="false"
			/>
			<kbd aria-hidden="true">/</kbd>
		</label>
		<div class="kinds" role="group" aria-label="Filter by what a tool does">
			{#each kinds as item}
				<button
					type="button"
					class:active={kind === item.id}
					aria-pressed={kind === item.id}
					onclick={() => (kind = item.id)}
				>
					{item.label}
				</button>
			{/each}
		</div>
		<p class="found" aria-live="polite">
			{filtering ? `${total} of ${data.toolCount} tools` : `${data.toolCount} tools`}
		</p>
	</div>

	<div class="catalogue-body">
		<nav class="group-nav" aria-label="Tool groups">
			{#each data.groups as group}
				{@const match = shown.find((item) => item.id === group.id)}
				<a href={`#${group.id}`} class:active={activeGroup === group.id} class:empty={!match}>
					<span>{group.title}</span><b>{match ? countOf(match) : 0}</b>
				</a>
			{/each}
		</nav>

		<div class="tool-groups">
			{#each shown as group (group.id)}
				<section class="tool-group" id={group.id} aria-labelledby={`${group.id}-title`}>
					<div class="group-head">
						<h2 id={`${group.id}-title`}>{group.title}</h2>
						<p>{group.text}</p>
					</div>
					{#each group.categories as category (category.id)}
						<div class="tool-category">
							<h3>{category.title}<span>{category.tools.length}</span></h3>
							<ul class="tool-list">
								{#each category.tools as tool (tool.name)}
									<li class="tool-row wipe">
										<div class="tool-head">
											<h4>{tool.label}</h4>
											<span class={`kind kind-${tool.access}`}><i></i>{kindName[tool.access]}</span>
										</div>
										<p>{tool.summary}</p>
										<code>{tool.name}</code>
									</li>
								{/each}
							</ul>
						</div>
					{/each}
				</section>
			{:else}
				<div class="no-tools">
					<p>No tools match “{query}”{kind === 'all' ? '' : ` in ${kindName[kind]}`}.</p>
					<button type="button" class="button ghost" data-magnetic onclick={clear}
						><span>Clear search</span></button
					>
				</div>
			{/each}
		</div>
	</div>

	<section class="catalogue-more">
		<p>
			Need something else? Connect any of 500+ apps through Composio, or add an MCP server or skill.
		</p>
		<a class="button" data-magnetic href="/#download"><span>Get Triangle</span><Tri /></a>
	</section>
</main>
