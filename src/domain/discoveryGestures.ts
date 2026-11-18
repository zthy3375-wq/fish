// Deliberate repeated activations. A pause starts a new sequence.
export function tapSequence(goal:number,maxGap=750){
  let count=0, previous=-Infinity;
  function reset(){count=0;previous=-Infinity;}
  function tap(now=performance.now()){
    if(now-previous>maxGap||now<previous)count=0;
    previous=now;
    if(++count<goal)return false;
    reset();return true;
  }
  return {tap,reset};
}

export function weekJourney(){
  let visited=false;
  return {
    reset(){visited=false;},
    move(from:number,to:number,current:number){
      if(current<=1||from===to)return false;
      if(to===1)visited=true;
      if(visited&&to===current){visited=false;return true;}
      return false;
    }
  };
}
