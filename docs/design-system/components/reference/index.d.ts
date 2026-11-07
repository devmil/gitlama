import type * as React from 'react';
type Lane = 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8;
type RowState = 'selected' | 'focused';

export interface IconProps { name: string; size?: 'sm'; stroke?: number; className?: string }
export declare function Icon(props: IconProps): React.ReactElement;
export interface KbdProps { keys: string[] }
export declare function Kbd(props: KbdProps): React.ReactElement;
export interface CountProps { tone?: 'polar' | 'conflict' | 'quiet'; children: React.ReactNode }
export declare function Count(props: CountProps): React.ReactElement;

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'secondary' | 'primary' | 'quiet' | 'danger' | 'danger-quiet'; size?: 'sm'; icon?: string; kbd?: string[]; loading?: boolean }
export declare function Button(props: ButtonProps): React.ReactElement;
export interface IconButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> { icon: string; label: string; size?: 'sm'; active?: boolean; onGround?: boolean }
export declare function IconButton(props: IconButtonProps): React.ReactElement;
export interface ToolbarButtonProps { icon: string; label: string; badge?: number; menu?: boolean; disabled?: boolean; title?: string }
export declare function ToolbarButton(props: ToolbarButtonProps): React.ReactElement;

export interface TextFieldProps { placeholder?: string; value?: string; icon?: string; trailing?: string; variant?: 'search'; size?: 'sm'; error?: boolean; message?: string; label?: string; width?: number }
export declare function TextField(props: TextFieldProps): React.ReactElement;
export interface SegmentedOption { value: string; label?: string; icon?: string; title?: string }
export interface SegmentedProps { options: SegmentedOption[]; value?: string; onChange?: (v: string) => void; size?: 'sm'; label?: string }
export declare function Segmented(props: SegmentedProps): React.ReactElement;
export interface CheckboxProps { checked?: boolean; mixed?: boolean; disabled?: boolean; children?: React.ReactNode }
export declare function Checkbox(props: CheckboxProps): React.ReactElement;
export interface SwitchProps { checked?: boolean; children?: React.ReactNode }
export declare function Switch(props: SwitchProps): React.ReactElement;
export interface SelectProps { value: string; width?: number }
export declare function Select(props: SelectProps): React.ReactElement;
export type MenuItem = { type: 'sep' } | { type: 'header'; label: string } |
  { label: React.ReactNode; icon?: string; kbd?: string[]; hint?: string; danger?: boolean; disabled?: boolean; hl?: boolean };
export interface MenuProps { items: MenuItem[]; width?: number }
export declare function Menu(props: MenuProps): React.ReactElement;

export interface CompassProps { repo: string; branch: string; detached?: boolean; ahead?: number; behind?: number; dirty?: number; conflicts?: number; operation?: string; progress?: number }
export declare function Compass(props: CompassProps): React.ReactElement;
export interface SyncBadgeProps { ahead?: number; behind?: number; showZero?: boolean }
export declare function SyncBadge(props: SyncBadgeProps): React.ReactElement | null;
export interface RepoTab { name: string; dirty?: boolean; hint?: string }
export interface RepoTabsProps { tabs: RepoTab[]; active: number }
export declare function RepoTabs(props: RepoTabsProps): React.ReactElement;
export interface SidebarSectionProps { title: string; count?: number; action?: string; children?: React.ReactNode }
export declare function SidebarSection(props: SidebarSectionProps): React.ReactElement;
export interface SidebarRowProps { name: string; icon?: string; depth?: number; expandable?: boolean; open?: boolean; current?: boolean; ahead?: number; behind?: number; count?: number; state?: RowState }
export declare function SidebarRow(props: SidebarRowProps): React.ReactElement;
export interface PaletteGroup { title: string; items: MenuItem[] }
export interface PaletteProps { query: string; groups: PaletteGroup[] }
export declare function Palette(props: PaletteProps): React.ReactElement;

export interface IslandProps { title?: string; subtitle?: React.ReactNode; actions?: React.ReactNode; focused?: boolean; style?: React.CSSProperties; bodyStyle?: React.CSSProperties; children?: React.ReactNode }
export declare function Island(props: IslandProps): React.ReactElement;
export interface DialogProps { title: string; description?: string; aside?: React.ReactNode; actions: React.ReactNode; children?: React.ReactNode }
export declare function Dialog(props: DialogProps): React.ReactElement;
export interface SettingsRowProps { label: string; help?: string; children: React.ReactNode }
export declare function SettingsRow(props: SettingsRowProps): React.ReactElement;
export declare function SettingsGroup(props: { children: React.ReactNode; style?: React.CSSProperties }): React.ReactElement;

export interface StatusGlyphProps { status: 'M' | 'A' | 'D' | 'R' | 'C' | 'U' | '?' | '!' }
export declare function StatusGlyph(props: StatusGlyphProps): React.ReactElement;
export interface RefChipProps { kind?: 'head' | 'local' | 'remote' | 'tag' | 'stash'; name: string; lane?: Lane; upstream?: string; ahead?: number; behind?: number; title?: string }
export declare function RefChip(props: RefChipProps): React.ReactElement;
export interface AvatarProps { name: string; lane?: Lane; size?: 'lg' }
export declare function Avatar(props: AvatarProps): React.ReactElement;
export type GraphSeg =
  | { t: 'v' | 'top' | 'bot'; c: number; lane?: Lane; faint?: boolean }
  | { t: 'in' | 'out' | 'x'; from: number; to: number; lane?: Lane; faint?: boolean };
export interface GraphProps { cols?: number; height?: number; segs?: GraphSeg[]; node?: { c: number; lane?: Lane; kind?: 'commit' | 'head' | 'merge' | 'stash' | 'wip' } }
export declare function Graph(props: GraphProps): React.ReactElement;
export interface CommitRowProps { graph?: GraphProps; subject: string; refs?: RefChipProps[]; author?: string; hash?: string; when?: string; state?: RowState; wip?: boolean; dim?: boolean; graphWidth?: number; authorWidth?: number }
export declare function CommitRow(props: CommitRowProps): React.ReactElement;
export interface FileRowProps { status: StatusGlyphProps['status']; path: string; add?: number; del?: number; staged?: boolean; state?: RowState; depth?: number }
export declare function FileRow(props: FileRowProps): React.ReactElement;
export interface DiffLine { t: ' ' | '+' | '-'; o?: number; n?: number; text: string; picked?: boolean }
export interface DiffHunkProps { range: string; context?: string; lines: DiffLine[]; staged?: boolean; picked?: boolean }
export declare function DiffHunk(props: DiffHunkProps): React.ReactElement;
export interface ComposerProps { subject?: string; body?: string; staged: number; branch?: string; amend?: boolean }
export declare function Composer(props: ComposerProps): React.ReactElement;

export interface BannerProps { tone?: 'info' | 'warning' | 'conflict' | 'error'; title?: string; icon?: string; actions?: React.ReactNode; children?: React.ReactNode }
export declare function Banner(props: BannerProps): React.ReactElement;
export interface LogEntry { status: 'run' | 'ok' | 'warn' | 'fail'; verb: string; target?: string; meta?: string; time: string; command?: string; output?: string }
export interface LogbookProps { entries: LogEntry[] }
export declare function Logbook(props: LogbookProps): React.ReactElement;
