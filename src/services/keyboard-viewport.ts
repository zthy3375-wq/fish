/** Pinch zoom and a collapsed URL bar are not evidence of a software keyboard. */
export function keyboardViewport(height:number, viewport:{height:number;scale:number}|null, focused:Element|null) {
 const editable=focused?.matches('textarea,input:not([type=checkbox]):not([type=radio]):not([type=button]):not([type=submit]),[contenteditable=true]');
 return !!editable&&!!viewport&&Math.abs(viewport.scale-1)<0.05&&height-viewport.height>150;
}
