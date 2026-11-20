const chinaYear = new Intl.DateTimeFormat('en', {year:'numeric',timeZone:'Asia/Shanghai'});

export const collectionActions = [
  'collection.profile', 'collection.archive', 'collection.wear', 'collection.visibility',
  'collection.ack', 'collection.showcase', 'collection.admin', 'collection.change',
];

export function sanitizeHonorCollection(action, body, { text, id, oneOf, boolean, fail }) {
  function number(value, min, max) {
    if (!Number.isInteger(value) || value < min || value > max) fail();
    return value;
  }
  const offset = value => number(value ?? 0, 0, 10000);
  const year = value => value == null ? null : number(value, 2020, Number(chinaYear.format(new Date())) + 1);
  switch (action) {
    case 'collection.profile':
      return { memberId: id(body.memberId, true), offset: offset(body.offset) };
    case 'collection.archive':
      return {
        section: oneOf(body.section ?? 'legend', ['legend', 'annual', 'contribution', 'retired']),
        year: year(body.year), offset: offset(body.offset),
      };
    case 'collection.wear':
      return { awardId: id(body.awardId, true), useTitle: body.useTitle === true,
        legacyCode: body.legacyCode == null ? null : oneOf(body.legacyCode, ['seed','creator','contributor']),
        organized: body.organized === true };
    case 'collection.showcase': {
      const original = ['arrival','firstpost','hello','liked','sprout','neighbor','popular','collector','month','year'];
      if (!Array.isArray(body.items) || body.items.length > 3 || new Set(body.items).size !== body.items.length) fail();
      return { items: body.items.map(value => original.includes(value) ? value : id(value)) };
    }
    case 'collection.visibility':
      return { awardId: id(body.awardId), public: boolean(body.public) };
    case 'collection.ack': {
      if (!Array.isArray(body.awardIds) || body.awardIds.length > 30) fail();
      return { awardIds: [...new Set(body.awardIds.map(value => id(value)))] };
    }
    case 'collection.admin':
      return {
        memberId: id(body.memberId, true), query: text(body.query ?? '', 0, 64),
        exceptions: body.exceptions === true, offset: offset(body.offset),
        definitionOffset: offset(body.definitionOffset), grantOffset: offset(body.grantOffset),
        definitionScope: body.definitionScope == null ? null : oneOf(body.definitionScope, ['honor','achievement']),
      };
    case 'collection.change':
      break;
    default:
      fail();
  }
  const operation = oneOf(body.operation, ['save', 'archive', 'title', 'grant', 'revoke']);
  const common = { operation, requestId: id(body.requestId), reason: text(body.reason, 2, 240) };
  if (operation === 'archive') return { ...common, definitionId: id(body.definitionId) };
  if (operation === 'title') return { ...common, memberId: id(body.memberId), title: text(body.title ?? '', 0, 16) };
  if (operation === 'revoke') return { ...common, awardId: id(body.awardId) };
  if (operation === 'grant') return {
    ...common, memberId: id(body.memberId), definitionId: id(body.definitionId),
    story: text(body.story, 2, 240), evidence: text(body.evidence, 4, 400),
  };
  const definitionId = id(body.definitionId, true);
  const edit = {
    ...common, definitionId, name: text(body.name, 2, 24), criteria: text(body.criteria, 2, 240),
    story: text(body.story, 2, 240), capacity: body.capacity == null ? null : number(body.capacity, 1, 10000),
  };
  if (definitionId) return edit;
  const code = text(body.code, 2, 48);
  if (!/^[a-z][a-z0-9-]{1,47}$/.test(code)) fail();
  const category = oneOf(body.category, ['identity', 'contribution', 'legend', 'limited', 'hidden']);
  const editionYear = year(body.year);
  if ((category === 'limited') !== (editionYear !== null) ||
      (editionYear !== null && !code.endsWith('-' + editionYear))) fail();
  return { ...edit, code, category, year: editionYear, rarity: oneOf(body.rarity, ['common', 'fine', 'rare', 'epic', 'legendary']) };
}
