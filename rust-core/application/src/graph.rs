//! Application-owned G-LANE-01 projection and bounded row geometry.

use std::collections::{HashMap, HashSet};

pub const HISTORY_PAGE_CAPACITY: usize = crate::domain::limits::PAGE_ROWS;
pub const LANE_PITCH: f64 = 14.0;
pub const LANE_ORIGIN_X: f64 = 9.0;
pub const CONTENT_GAP: f64 = 8.0;
pub const METADATA_GAP: f64 = 12.0;
pub const METADATA_FIELD_GAP: f64 = 12.0;
pub const METADATA_RIGHT_INSET: f64 = 12.0;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum GraphNodeShape {
    Commit,
    Merge,
    Boundary,
    Graft,
    Replace,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum GraphBoundary {
    Shallow,
    Missing,
    Graft,
    OutsideWindow,
    CollapsedMerge,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum GraphSegmentKind {
    Straight,
    Join,
    Merge,
    Octopus,
    Boundary,
    Missing,
    CollapsedMerge,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GraphCommit {
    pub id: String,
    pub parents: Vec<String>,
    pub shape: GraphNodeShape,
    pub boundary: Option<GraphBoundary>,
    pub missing_parents: HashSet<String>,
}

impl GraphCommit {
    pub fn topology(id: String, parents: Vec<String>) -> Self {
        let shape = if parents.len() > 1 {
            GraphNodeShape::Merge
        } else {
            GraphNodeShape::Commit
        };
        Self {
            id,
            parents,
            shape,
            boundary: None,
            missing_parents: HashSet::new(),
        }
    }

    fn edge_boundary(&self, parent: &str) -> Option<GraphBoundary> {
        if self.missing_parents.contains(parent) {
            Some(GraphBoundary::Missing)
        } else {
            self.boundary
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GraphSegment {
    pub from: String,
    pub to: String,
    pub parent_ordinal: usize,
    pub from_lane: usize,
    pub to_lane: usize,
    pub kind: GraphSegmentKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GraphLayout {
    pub lanes: HashMap<String, usize>,
    pub segments: Vec<GraphSegment>,
    pub lane_count: usize,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GraphRowGeometry {
    pub metadata_left: f64,
    pub graph_clip_right: f64,
    pub content_start: f64,
    pub content_available: f64,
}

/// Applies the design-system G-LANE-01 assignment to a complete or provisional topology.
pub fn layout_graph(
    commits: &[GraphCommit],
    visible_order: &[String],
    head: Option<&str>,
    collapsed_edges: &HashSet<(String, String)>,
    include_wip: bool,
) -> Result<GraphLayout, &'static str> {
    let indexed = commits
        .iter()
        .map(|commit| (commit.id.as_str(), commit))
        .collect::<HashMap<_, _>>();
    if indexed.len() != commits.len() {
        return Err("duplicate commit identity");
    }
    if head.is_some_and(|id| !indexed.contains_key(id)) {
        return Err("HEAD is absent from topology");
    }
    let mut visible = HashSet::with_capacity(visible_order.len());
    if visible_order
        .iter()
        .any(|id| !visible.insert(id.as_str()) || !indexed.contains_key(id.as_str()))
    {
        return Err("visible history is duplicated or absent from topology");
    }

    let spine = first_parent_spine(head, &indexed);
    let mut reservations: Vec<Option<String>> = Vec::new();
    let mut lanes = HashMap::with_capacity(visible_order.len());
    let mut edge_lanes = HashMap::<(&str, usize), usize>::new();
    for id in visible_order {
        let commit = indexed[id.as_str()];
        let lane = if spine.contains(id.as_str()) {
            ensure_lane(&mut reservations, 0);
            0
        } else {
            find_reservation(&reservations, id)
                .unwrap_or_else(|| lowest_free_lane(&mut reservations, 1))
        };
        lanes.insert(id.clone(), lane);
        // A side branch remains live until its actual spine parent. Release
        // those lanes at the parent row, after the row has its own lane.
        if spine.contains(id.as_str()) {
            for reserved in reservations.iter_mut().skip(1) {
                if reserved.as_deref() == Some(id.as_str()) {
                    *reserved = None;
                }
            }
        }

        if commit.parents.is_empty() {
            reservations[lane] = None;
            continue;
        }
        let first_parent = &commit.parents[0];
        if commit.edge_boundary(first_parent).is_some() {
            edge_lanes.insert((id.as_str(), 0), lane);
            reservations[lane] = None;
        } else {
            let first_parent_lane = if spine.contains(first_parent.as_str()) {
                0
            } else {
                find_reservation(&reservations, first_parent).unwrap_or(lane)
            };
            edge_lanes.insert((id.as_str(), 0), first_parent_lane);
            if spine.contains(first_parent.as_str()) {
                if spine.contains(id.as_str()) {
                    ensure_lane(&mut reservations, 0);
                    reservations[0] = Some(first_parent.clone());
                    if lane != 0 {
                        reservations[lane] = None;
                    }
                } else {
                    reservations[lane] = visible
                        .contains(first_parent.as_str())
                        .then(|| first_parent.clone());
                }
            } else if let Some(other_lane) = find_reservation(&reservations, first_parent) {
                if other_lane != lane {
                    reservations[lane] = None;
                }
            } else {
                reservations[lane] = Some(first_parent.clone());
            }
        }
        for (parent_ordinal, parent) in commit.parents.iter().enumerate().skip(1) {
            if commit.edge_boundary(parent).is_some() {
                edge_lanes.insert(
                    (id.as_str(), parent_ordinal),
                    lowest_free_lane(&mut reservations, 1),
                );
            } else if spine.contains(parent.as_str()) {
                ensure_lane(&mut reservations, 0);
                edge_lanes.insert((id.as_str(), parent_ordinal), 0);
            } else {
                let extra_lane = find_reservation(&reservations, parent).unwrap_or_else(|| {
                    let extra_lane = lowest_free_lane(&mut reservations, 1);
                    reservations[extra_lane] = Some(parent.clone());
                    extra_lane
                });
                edge_lanes.insert((id.as_str(), parent_ordinal), extra_lane);
            }
        }
    }

    if include_wip {
        lanes.insert("wip".to_owned(), 0);
    }
    let mut segments = Vec::new();
    if include_wip {
        if let Some(head) = head {
            segments.push(GraphSegment {
                from: "wip".to_owned(),
                to: head.to_owned(),
                parent_ordinal: 0,
                from_lane: 0,
                to_lane: lanes.get(head).copied().unwrap_or(0),
                kind: GraphSegmentKind::Straight,
            });
        }
    }
    for id in visible_order {
        let commit = indexed[id.as_str()];
        let from_lane = lanes[id];
        for (parent_ordinal, parent) in commit.parents.iter().enumerate() {
            let boundary = commit.edge_boundary(parent);
            let to_lane = lanes
                .get(parent)
                .copied()
                .or_else(|| edge_lanes.get(&(id.as_str(), parent_ordinal)).copied())
                .unwrap_or(from_lane);
            // Probing the set allocates a key; most views collapse nothing.
            let kind = if !collapsed_edges.is_empty()
                && collapsed_edges.contains(&(id.clone(), parent.clone()))
            {
                GraphSegmentKind::CollapsedMerge
            } else if boundary == Some(GraphBoundary::Missing) {
                GraphSegmentKind::Missing
            } else if boundary.is_some() && boundary != Some(GraphBoundary::OutsideWindow) {
                GraphSegmentKind::Boundary
            } else if parent_ordinal > 0 {
                if commit.parents.len() > 2 {
                    GraphSegmentKind::Octopus
                } else {
                    GraphSegmentKind::Merge
                }
            } else if from_lane == to_lane {
                GraphSegmentKind::Straight
            } else {
                GraphSegmentKind::Join
            };
            segments.push(GraphSegment {
                from: id.clone(),
                to: parent.clone(),
                parent_ordinal,
                from_lane,
                to_lane,
                kind,
            });
        }
    }
    let lane_count = lanes
        .values()
        .copied()
        .chain(
            segments
                .iter()
                .flat_map(|segment| [segment.from_lane, segment.to_lane]),
        )
        .max()
        .map_or(0, |lane| lane + 1);
    Ok(GraphLayout {
        lanes,
        segments,
        lane_count,
    })
}

/// Resolves shared graph/ref/message and pinned metadata geometry from measured field widths.
pub fn row_geometry(
    row_width: f64,
    field_widths: &[f64],
    ink_right_by_primitive: &[f64],
) -> GraphRowGeometry {
    let fields = field_widths.iter().sum::<f64>();
    let between_fields = METADATA_FIELD_GAP * field_widths.len().saturating_sub(1) as f64;
    let metadata_left = (row_width - METADATA_RIGHT_INSET - fields - between_fields).max(0.0);
    let graph_clip_right = (metadata_left - METADATA_GAP).max(0.0);
    let content_start = ink_right_by_primitive
        .iter()
        .copied()
        .reduce(f64::max)
        .map_or(LANE_ORIGIN_X, |right| (right + CONTENT_GAP).ceil());
    GraphRowGeometry {
        metadata_left,
        graph_clip_right,
        content_start,
        content_available: (graph_clip_right - content_start).max(0.0),
    }
}

fn first_parent_spine<'a>(
    head: Option<&'a str>,
    commits: &HashMap<&str, &'a GraphCommit>,
) -> HashSet<&'a str> {
    let mut spine = HashSet::new();
    let mut current = head;
    while let Some(id) = current {
        if !spine.insert(id) {
            break;
        }
        current = commits
            .get(id)
            .and_then(|commit| commit.parents.first())
            .map(String::as_str);
    }
    spine
}

fn ensure_lane(lanes: &mut Vec<Option<String>>, index: usize) {
    if lanes.len() <= index {
        lanes.resize(index + 1, None);
    }
}

fn lowest_free_lane(lanes: &mut Vec<Option<String>>, minimum: usize) -> usize {
    if lanes.len() < minimum {
        lanes.resize(minimum, None);
    }
    if let Some(index) = (minimum..lanes.len()).find(|index| lanes[*index].is_none()) {
        index
    } else {
        lanes.push(None);
        lanes.len() - 1
    }
}

fn find_reservation(lanes: &[Option<String>], id: &str) -> Option<usize> {
    lanes
        .iter()
        .position(|reserved| reserved.as_deref() == Some(id))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    const GRAPH_FIXTURES: &str =
        include_str!("../../../docs/design-system/specs/graph-fixtures.json");
    const ROW_FIXTURES: &str =
        include_str!("../../../docs/design-system/specs/graph-row-layout-fixtures.json");

    #[test]
    fn every_g_lane_01_fixture_matches_lanes_shapes_and_segments() {
        let document: Value = serde_json::from_str(GRAPH_FIXTURES).unwrap();
        assert_eq!(document["algorithm"], "G-LANE-01");
        for fixture in document["fixtures"].as_array().unwrap() {
            let mut commits = Vec::new();
            for raw in fixture["commits"].as_array().unwrap() {
                if raw["type"].as_str() == Some("wip") {
                    continue;
                }
                let id = raw["id"].as_str().unwrap().to_owned();
                let parents = strings(&raw["parents"]);
                let mut commit = GraphCommit::topology(id, parents);
                commit.shape = match raw["type"].as_str() {
                    Some("replace") => GraphNodeShape::Replace,
                    Some("graft") => GraphNodeShape::Graft,
                    _ if raw["boundary"].as_str() == Some("shallow") => GraphNodeShape::Boundary,
                    _ if commit.parents.len() > 1 => GraphNodeShape::Merge,
                    _ => GraphNodeShape::Commit,
                };
                commit.boundary = match raw["boundary"].as_str() {
                    Some("shallow") => Some(GraphBoundary::Shallow),
                    _ => None,
                };
                commit.missing_parents = strings(&raw["missingParents"]).into_iter().collect();
                commits.push(commit);
            }
            let order = strings(&fixture["visibleOrder"])
                .into_iter()
                .filter(|id| id != "wip")
                .collect::<Vec<_>>();
            let collapsed = fixture["collapsedGroups"]
                .as_array()
                .unwrap()
                .iter()
                .map(|group| {
                    (
                        group["mergeId"].as_str().unwrap().to_owned(),
                        group["sideParent"].as_str().unwrap().to_owned(),
                    )
                })
                .collect();
            let layout = layout_graph(
                &commits,
                &order,
                fixture["head"].as_str(),
                &collapsed,
                fixture.get("wip").is_some_and(|value| !value.is_null()),
            )
            .unwrap_or_else(|error| panic!("{}: {error}", fixture["id"]));
            for (id, lane) in fixture["expectedLanes"].as_object().unwrap() {
                assert_eq!(
                    layout.lanes.get(id),
                    lane.as_u64().map(|v| v as usize).as_ref(),
                    "{} lane {id}",
                    fixture["id"]
                );
            }
            for (id, shape) in fixture["expectedShapes"].as_object().unwrap() {
                if id == "wip" {
                    continue;
                }
                let actual = commits
                    .iter()
                    .find(|commit| commit.id == *id)
                    .unwrap()
                    .shape;
                assert_eq!(
                    shape_name(actual),
                    shape.as_str().unwrap(),
                    "{} shape {id}",
                    fixture["id"]
                );
            }
            for expected in fixture["expectedLaneSegments"].as_array().unwrap() {
                let actual = layout
                    .segments
                    .iter()
                    .find(|segment| {
                        segment.from == expected["from"].as_str().unwrap()
                            && segment.to == expected["to"].as_str().unwrap()
                    })
                    .unwrap_or_else(|| panic!("{} missing segment", fixture["id"]));
                assert_eq!(
                    actual.from_lane,
                    expected["fromLane"].as_u64().unwrap() as usize
                );
                assert_eq!(
                    actual.to_lane,
                    expected["toLane"].as_u64().unwrap() as usize
                );
                assert_eq!(
                    segment_name(actual.kind),
                    expected["kind"].as_str().unwrap()
                );
            }
        }
    }

    #[test]
    fn row_geometry_matches_every_design_oracle_case() {
        let document: Value = serde_json::from_str(ROW_FIXTURES).unwrap();
        for case in document["cases"].as_array().unwrap() {
            let fields = numbers(&case["fieldWidths"]);
            let ink = numbers(&case["inkRightByPrimitive"]);
            let geometry = row_geometry(case["rowWidth"].as_f64().unwrap(), &fields, &ink);
            let expected = &case["expected"];
            assert_eq!(
                geometry.metadata_left,
                expected["metadataLeft"].as_f64().unwrap(),
                "{}",
                case["id"]
            );
            assert_eq!(
                geometry.graph_clip_right,
                expected["graphClipRight"].as_f64().unwrap(),
                "{}",
                case["id"]
            );
            assert_eq!(
                geometry.content_start,
                expected["contentStart"].as_f64().unwrap(),
                "{}",
                case["id"]
            );
            assert_eq!(
                geometry.content_available,
                expected["contentAvailable"].as_f64().unwrap(),
                "{}",
                case["id"]
            );
        }
    }

    fn strings(value: &Value) -> Vec<String> {
        value
            .as_array()
            .map(|values| {
                values
                    .iter()
                    .map(|value| value.as_str().unwrap().to_owned())
                    .collect()
            })
            .unwrap_or_default()
    }

    fn numbers(value: &Value) -> Vec<f64> {
        value
            .as_array()
            .unwrap()
            .iter()
            .map(|value| value.as_f64().unwrap())
            .collect()
    }

    const fn shape_name(shape: GraphNodeShape) -> &'static str {
        match shape {
            GraphNodeShape::Commit => "commit",
            GraphNodeShape::Merge => "merge",
            GraphNodeShape::Boundary => "boundary",
            GraphNodeShape::Graft => "graft",
            GraphNodeShape::Replace => "replace",
        }
    }

    const fn segment_name(kind: GraphSegmentKind) -> &'static str {
        match kind {
            GraphSegmentKind::Straight => "straight",
            GraphSegmentKind::Join => "join",
            GraphSegmentKind::Merge => "merge",
            GraphSegmentKind::Octopus => "octopus",
            GraphSegmentKind::Boundary => "boundary",
            GraphSegmentKind::Missing => "missing",
            GraphSegmentKind::CollapsedMerge => "collapsed-merge",
        }
    }
}
