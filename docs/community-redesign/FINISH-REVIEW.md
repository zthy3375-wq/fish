disposition: fix

Evidence scope: all 21 explicitly required Chromium fixture captures opened and valid: seven named surfaces at 360/390/430; standard captures are 844px high and short-reply captures 520px high. These are browser evidence, not Android device acceptance. This is a code-led extension of an established system; approved comp, direction roll, quality board and comp-diff artifacts do not apply. No mechanical detector result was supplied or claimed. Primary files were sampled; unrelated flows and the broader regression run were not reviewed.

## persistence

Pass. PRODUCT.md, DESIGN.md and docs/community-redesign/BRIEF.md persist the product, established purple/white system, five-tab structure and community scope. The screenshots retain the documented navigation and reading/writing hierarchy. Comp-phase state and a new identity contract are not prerequisites for this extension. The existing goldfish/home surface lies outside these captures and is not independently certified here.

## fidelity

| Element | Verdict | Evidence |
| --- | --- | --- |
| TYPE | match | System Chinese business typography follows DESIGN.md and the Operate/Read brief. Post titles, body copy, author names and metadata have distinct levels; 360px wrapping stays readable. |
| MATERIAL | match | Flat white reading surfaces, pale-purple context areas and consistent drawn icons suit the established UI. No imitation physical material is introduced. |
| GROUND | match | Light captures retain white content with the documented pale purple grouping; the dark capture preserves the existing cool dark theme rather than introducing another identity. |
| Feed hierarchy and five-tab shell | match | 广场/关注/继续聊, topic filters, author/content/media/actions and 首页/课表/社区/待办/我的 remain visible. Post boundaries and the action divider organize the feed. |
| Detail and long image | match | 正文/评论 navigation and the fixed reply/like/save/comment bar are clear at all three widths. The long image remains legible and continues below the viewport. |
| Comments and reply chains | match | Parent author/body/time/reply ordering and the indented pale reply block make the conversation structure explicit; nested bylines identify the recipient. |
| Composer | match | Identity and destination precede the continuous title/body writing area; attachment preview, attachment tools, saved-draft status and identity explanation remain visible. |
| Reply attachment control | contradicted | In all six editor/short-reply captures, the image icon and “配图 0/3” run together against the tile's top edge, leaving its interior blank. The generic `.treehole label:not(...)` rule in Treehole.css overrides the intended flex-column tile layout. This weakens the promised clear writing controls. |
| Dark primary action | contradicted | All three dark feed captures show white “发帖” text and a white pen on a light-blue FAB. At 390px, sampled fill is RGB(164,187,217), giving approximately 1.96:1 against white, below the craft floor for both the label and meaningful icon. Treehole.css hard-codes `.th-fab { color:white }`. |

## ceiling

The established quiet UI's useful devices—typographic hierarchy, white reading space, pale-purple conversation grouping and restrained dividers—are present. More ornament, replacement typography or an authored illustration would conflict with this scope. The remaining finish gap is concentrated in the attachment affordance and dark primary-action contrast; native keyboard/insets and device behavior remain outside this browser review.

## material_fixes

1. Floor / contrast: give the dark-theme FAB a theme-aware foreground/background pair with at least 4.5:1 for its label and 3:1 for its pen icon; verify expanded and collapsed states at 360/390/430 without changing the light purple action.
2. Contract / clear writing controls: exclude the comment-image picker from the generic label override, or give its scoped layout sufficient specificity, so the image icon and count form a centered vertical group with visible separation; recapture both full-height and 520px reply editors at all three widths.

## keep

Keep the flat reading rhythm, explicit nested reply recipients, continuous writing surface, visible identity choice, shared palette and five-tab navigation while applying these fixes.

## verdict

1. Resolved — dark primary-action contrast: the refreshed expanded FABs at 360/390/430 visibly use dark lettering and pen strokes on the existing light-blue fill. The three additional `community-dark-collapsed-<width>.png` captures show the same dark pen clearly in the collapsed circle. The light purple action remains visually unchanged.
2. Resolved — reply attachment control: all six refreshed full-height and 520px reply-editor captures show the image icon centered above “配图 0/3”, with clear separation and balanced space inside the tile. The corrected group remains distinct from the writing field and footer at each width.

## remaining

Clear. All 21 original required captures and the three additional collapsed-FAB captures were reopened and are valid for their stated browser viewports; no regression introduced by these two fixes was observed. Ship covers the scored fixes, not the whole surface. This verdict covers Chromium fixture evidence and does not certify Android device acceptance.

disposition: ship
