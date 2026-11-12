// Organizes the tools exported from the app (see scripts/export_tools_test.dart)
// for the catalogue page. Only import this from server code: the lists are big.
import appTools from './app-tools.json';
import pcTools from './pc-tools.json';

type RawTool = {
	name: string;
	label: string;
	description: string;
	category: string;
	categoryLabel: string;
	access: string;
};

export type Tool = { name: string; label: string; summary: string; access: string };
export type Category = { id: string; title: string; tools: Tool[] };
export type Group = { id: string; title: string; text: string; categories: Category[] };

const plan = [
	{
		id: 'telegram',
		title: 'Telegram',
		text: 'A full Telegram client the assistant can use with your account.',
		from: 'app',
		categories: [
			'chats',
			'messages',
			'contacts',
			'folders',
			'media',
			'stories',
			'members',
			'bots',
			'calls',
			'analytics',
			'stars',
			'account'
		]
	},
	{
		id: 'assistant',
		title: 'Assistant',
		text: 'What it remembers, keeps safe, watches for, runs on a schedule, checks and makes.',
		from: 'app',
		categories: [
			'memory',
			'vault',
			'automation',
			'routines',
			'system',
			'canvas',
			'files',
			'imageTools',
			'creative',
			'decisions'
		]
	},
	{
		id: 'phone',
		title: 'Your phone',
		text: 'Texts, calls, notifications, screen time, alarms, and other apps it can read and use for you. Actions ask first.',
		from: 'app',
		categories: ['device', 'screen', 'callHistory', 'screenTime']
	},
	{
		id: 'money',
		title: 'Money',
		text: 'Your accounts and budgets, read from your bank texts, plus markets, prices and currencies.',
		from: 'app',
		categories: ['finance', 'markets', 'world']
	},
	{
		id: 'pc',
		title: 'Your PC',
		text: 'With Triangle Companion on Windows. Each group has its own switch on the PC.',
		from: 'pc',
		categories: ['info', 'files', 'screen', 'input', 'clipboard', 'commands', 'system']
	},
	{
		id: 'apps',
		title: 'Connected apps',
		text: 'Email, calendar, documents and work apps you choose to connect.',
		from: 'app',
		categories: [
			'gmail',
			'outlook',
			'calendar',
			'googleDocs',
			'slack',
			'notion',
			'githubAccount',
			'linear',
			'todoist',
			'apps'
		]
	},
	{
		id: 'web',
		title: 'Web and discovery',
		text: 'A real browser, YouTube, Reddit and Hacker News, research papers, books, podcasts, radio and more.',
		from: 'app',
		categories: ['web', 'youtube', 'discover', 'news', 'papers', 'library', 'developer', 'packages']
	},
	{
		id: 'everyday',
		title: 'Everyday',
		text: 'Words and translation, recipes, sports, the Bible, the Ethiopian calendar, QR codes, retro games and the wider world.',
		from: 'app',
		categories: ['reference', 'food', 'sports', 'bible', 'utilities', 'explore', 'games']
	},
	{
		id: 'cloud',
		title: 'Cloud and code',
		text: 'Run code, manage your cloud, and add more tools yourself.',
		from: 'app',
		categories: ['code', 'e2b', 'cloudflare', 'r2', 'mcp', 'skills']
	}
];

/** The first sentence of a description, short enough to scan. */
function summarize(description: string) {
	const first = description
		.replace(/\s+/g, ' ')
		.trim()
		.split(/(?<=[a-z0-9)"'’][.!?])(?<!\be\.g\.|\bi\.e\.)\s+/)[0]
		// Descriptions are written for the AI: "Tool to add a task for the user."
		.replace(/^Tool to (\w)/, (_, letter: string) => letter.toUpperCase())
		.replace(/\bthe (authenticated )?user's\b/gi, 'your')
		.replace(/\bthe (authenticated )?user (hasn't|has not)\b/gi, 'you haven’t')
		.replace(/\bthe (authenticated )?user has\b/gi, 'you have')
		.replace(/\bthe (authenticated )?user\b/gi, 'you');
	if (first.length <= 150) return first;
	const cut = first.slice(0, 150);
	const at = Math.max(cut.lastIndexOf(': '), cut.lastIndexOf(', '), cut.lastIndexOf('; '));
	return `${(at > 70 ? cut.slice(0, at) : cut.slice(0, cut.lastIndexOf(' '))).trim()}…`;
}

function build(): Group[] {
	const sources: Record<string, RawTool[]> = { app: appTools, pc: pcTools };
	return plan.map((group) => ({
		id: group.id,
		title: group.title,
		text: group.text,
		categories: group.categories.flatMap((id) => {
			const tools = sources[group.from].filter((tool) => tool.category === id);
			if (tools.length === 0) return [];
			return [
				{
					id: `${group.id}-${id}`,
					title: tools[0].categoryLabel,
					tools: tools.map((tool) => ({
						name: tool.name,
						label: tool.label,
						summary: summarize(tool.description),
						access: tool.access
					}))
				}
			];
		})
	}));
}

export const groups = build();
export const toolCount = groups.reduce(
	(all, group) => all + group.categories.reduce((sum, category) => sum + category.tools.length, 0),
	0
);
export const sourceCount = appTools.length + pcTools.length;
